import AppKit
import EventKit
import Observation

/// Um evento do calendário, já pronto para a ilha. O título vem de convites de outras pessoas: é dado de fora,
/// limpo como o de uma `Atividade` e nunca registrado no log.
struct EventoAgenda: Equatable, Identifiable, Sendable {
    /// Identificador da série + início: o `calendarItemIdentifier` se repete em cada ocorrência de um evento recorrente.
    var id: String
    var titulo: String
    var inicio: Date
    var fim: Date
    var diaInteiro = false
    /// A pessoa recusou o convite: não vai, então não lembra nem mostra.
    var recusado = false
    /// A cor do calendário em sRGB, para a barrinha ao lado do título.
    var cor: SIMD3<Double>?
    /// Só um link que passou por `EventoAgenda.link`: é o único que `Agenda.entrar` abre.
    var link: URL?

    /// Mostrar o que está acontecendo só nos primeiros minutos: é quando o botão "Entrar" importa (chegar atrasado).
    /// Depois disso a pessoa já entrou ou desistiu, e o próximo compromisso é mais útil que uma reunião longa.
    static let tolerancia: TimeInterval = 10 * 60
    static let horizonte: TimeInterval = 12 * 3600

    /// O evento da faixa "Hoje": o que começou há menos de `tolerancia` ou o primeiro das próximas 12 horas.
    static func proximo(_ eventos: [EventoAgenda], agora: Date) -> EventoAgenda? {
        eventos
            .filter { e in
                guard !e.diaInteiro, !e.recusado, e.fim > agora else { return false }
                let desdeOInicio = agora.timeIntervalSince(e.inicio)
                return desdeOInicio < tolerancia && -desdeOInicio <= horizonte
            }
            .min { ($0.inicio, $0.titulo) < ($1.inicio, $1.titulo) }  // título desempata: a escolha não pisca entre refreshes
    }

    // MARK: Link da reunião

    /// Só serviços de videochamada conhecidos, e só https: o link vem de convites de qualquer pessoa,
    /// e o botão "Entrar" abre sem perguntar. Um domínio fora da lista fica no Calendário, não na ilha.
    static let servicos = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
                           "facetime.apple.com", "whereby.com"]

    /// O primeiro link de reunião, na ordem do campo URL, do local e das notas (onde o Google e o Outlook o põem).
    static func link(url: URL?, local: String?, notas: String?) -> URL? {
        if let url, aceito(url) { return url }
        for texto in [local, notas].compactMap({ $0 }) {
            if let achado = links(em: texto).first(where: aceito) { return achado }
        }
        return nil
    }

    static func aceito(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        // Sufixo com o ponto: "meet.google.com.evil.com" e "evilzoom.us" não passam.
        return servicos.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// O detector da Foundation acha links no meio do texto, entre `<…>` e com pontuação colada.
    private static func links(em texto: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: texto, range: NSRange(texto.startIndex..., in: texto)).compactMap(\.url)
    }

    // MARK: Lembretes

    enum Aviso: Equatable, Sendable {
        case faltam(minutos: Int)
        case comecando
    }

    struct Lembrete: Equatable, Sendable {
        let evento: EventoAgenda
        let aviso: Aviso
        /// O que já foi avisado: um de cada tipo por evento.
        var chave: String { evento.id + (aviso == .comecando ? "#0" : "#15") }
    }

    static let antecedencia: TimeInterval = 15 * 60
    /// O relógio bate uma vez por minuto e atrasa um pouco: 90 s garantem uma batida dentro da janela.
    static let janelaDoInicio: TimeInterval = 90

    /// Os avisos devidos agora. Só olha a hora atual, não o que passou: ao acordar o Mac, um evento que começou
    /// há 20 min não ganha "em 15 min" atrasado; um que começa em 3 min ganha "em 3 min".
    static func lembretes(_ eventos: [EventoAgenda], agora: Date, avisados: Set<String>) -> [Lembrete] {
        eventos.compactMap { e -> Lembrete? in
            guard !e.diaInteiro, !e.recusado else { return nil }
            let falta = e.inicio.timeIntervalSince(agora)
            let lembrete: Lembrete? = if falta > 0 && falta <= antecedencia {
                Lembrete(evento: e, aviso: .faltam(minutos: Int((falta / 60).rounded(.up))))
            } else if falta <= 0 && -falta < janelaDoInicio {
                Lembrete(evento: e, aviso: .comecando)
            } else {
                nil
            }
            return lembrete.flatMap { avisados.contains($0.chave) ? nil : $0 }
        }
    }
}

extension EventoAgenda {
    init(_ evento: EKEvent) {
        let titulo = Atividade.limpo(evento.title ?? "", ate: 60)
        let cor = evento.calendar?.cgColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) }
        self.init(id: "\(evento.calendarItemIdentifier)-\(Int(evento.startDate.timeIntervalSince1970))",
                  titulo: titulo.isEmpty ? String(localized: "Sem título") : titulo,
                  inicio: evento.startDate,
                  fim: evento.endDate,
                  diaInteiro: evento.isAllDay,
                  recusado: evento.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false,
                  cor: cor.map { SIMD3($0.redComponent, $0.greenComponent, $0.blueComponent) },
                  link: Self.link(url: evento.url, local: evento.location, notas: evento.notes))
    }
}

/// O calendário da pessoa na ilha: o próximo evento e os lembretes. Sem permissão, fica vazio e nada quebra.
@MainActor @Observable
final class Agenda {
    enum Acesso: Equatable { case naoPedido, permitido, negado }

    private(set) var proximo: EventoAgenda?
    private(set) var acesso: Acesso = .naoPedido

    @ObservationIgnored private let mural: Mural
    /// EKEventStore não é Sendable: fica na thread principal, com a Agenda.
    @ObservationIgnored private let loja = EKEventStore()
    @ObservationIgnored private var avisados: Set<String> = []
    @ObservationIgnored private var relogio: Task<Void, Never>?

    init(mural: Mural) {
        self.mural = mural
    }

    func iniciar() {
        guard relogio == nil else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            comecar()
        case .notDetermined:
            // Forte de propósito: a resposta chega uma vez só, e a Agenda vive enquanto o app vive.
            loja.requestFullAccessToEvents { permitido, _ in
                Task { @MainActor in
                    if permitido { self.comecar() } else { self.negar() }
                }
            }
        default:  // negado, restrito ou só escrita (que não lê eventos)
            negar()
        }
    }

    /// Abre a reunião do próximo evento. Só chega aqui link https de um serviço da lista (`EventoAgenda.aceito`).
    func entrar() {
        guard let link = proximo?.link, EventoAgenda.aceito(link) else { return }
        NSWorkspace.shared.open(link)
    }

    private func negar() {
        acesso = .negado
        registro.notice("agenda: sem acesso ao calendário")
    }

    private func comecar() {
        guard relogio == nil else { return }
        acesso = .permitido
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: loja, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.atualizar() }
        }
        // Ao acordar, o relógio pode ter dormido no meio de um lembrete: confere já, sem esperar a próxima batida.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.atualizar() }
        }
        relogio = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.atualizar()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // ponytail: relê as próximas 24 h do EventKit a cada minuto, na thread principal (milissegundos para um dia);
    // guardar a lista e só reler no EKEventStoreChanged se aparecer no perfil.
    private func atualizar() {
        let agora = Date.now
        let predicado = loja.predicateForEvents(withStart: agora, end: agora.addingTimeInterval(24 * 3600), calendars: nil)
        let eventos = loja.events(matching: predicado).map(EventoAgenda.init)
        let novo = EventoAgenda.proximo(eventos, agora: agora)
        if novo != proximo { proximo = novo }
        let devidos = EventoAgenda.lembretes(eventos, agora: agora, avisados: avisados)
        for lembrete in devidos {
            avisados.insert(lembrete.chave)
            let detalhe = switch lembrete.aviso {
            case .faltam(let minutos): String(localized: "em \(minutos) min")
            case .comecando: String(localized: "começando agora")
            }
            // Começando agora passa na frente de tudo: é a hora de entrar na reunião.
            mural.receber(Atividade(id: "agenda-\(lembrete.evento.id)", titulo: lembrete.evento.titulo, detalhe: detalhe,
                                    simbolo: "calendar", cor: "vermelho", expira: 60,
                                    prioridade: lembrete.aviso == .comecando ? "urgente" : "alta")) { [link = lembrete.evento.link] in
                // Com link de reunião (já conferido pela lista de serviços), entra nela; sem, abre o Calendário.
                if let link, EventoAgenda.aceito(link) {
                    NSWorkspace.shared.open(link)
                } else {
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
                                                       configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                }
            }
        }
        // Esquece o que já passou: só eventos ainda na janela podem pedir aviso de novo.
        let ids = Set(eventos.map(\.id))
        avisados = avisados.filter { ids.contains(String($0.prefix { $0 != "#" })) }
        if !devidos.isEmpty { registro.info("agenda: \(devidos.count) lembretes de \(eventos.count) eventos em 24 h") }
    }
}
