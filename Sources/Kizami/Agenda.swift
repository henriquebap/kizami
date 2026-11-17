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

    /// A aba "Hoje": o que ainda não acabou até a meia-noite, os de dia inteiro primeiro, sem os recusados.
    static func doDia(_ eventos: [EventoAgenda], agora: Date, calendario: Calendar = .current) -> [EventoAgenda] {
        let inicioDoDia = calendario.startOfDay(for: agora)
        let amanha = calendario.date(byAdding: .day, value: 1, to: inicioDoDia) ?? inicioDoDia.addingTimeInterval(24 * 3600)
        return eventos
            .filter { !$0.recusado && $0.fim > agora && $0.inicio < amanha }
            .sorted { ($0.diaInteiro ? 0 : 1, $0.inicio, $0.titulo) < ($1.diaInteiro ? 0 : 1, $1.inicio, $1.titulo) }
    }

    /// A reunião que vai para as asas da ilha fechada: começa em até 10 min ou começou há menos de 5. Dia inteiro não.
    static func naAsa(_ e: EventoAgenda?, agora: Date) -> EventoAgenda? {
        guard let e, !e.diaInteiro, !e.recusado else { return nil }
        let falta = e.inicio.timeIntervalSince(agora)
        return falta <= 10 * 60 && falta > -5 * 60 ? e : nil
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

/// Os dias da agenda expandida: a faixa da semana, a grade do mês e os eventos de cada dia. Puro: o `Calendar`
/// vem de fora (o primeiro dia da semana é o da pessoa, `Calendar.current`), e os testes usam um fixo.
enum Calendario {
    /// Os 7 dias da semana de `dia`, começando no primeiro dia da semana do calendário, à meia-noite.
    static func semana(de dia: Date, calendario: Calendar) -> [Date] {
        let inicio = calendario.dateInterval(of: .weekOfYear, for: dia)?.start ?? calendario.startOfDay(for: dia)
        return dias(desde: inicio, total: 7, calendario: calendario)
    }

    /// A grade do mês de `dia`: semanas inteiras, da que tem o dia 1 à que tem o último (4 a 6 fileiras de 7).
    static func mes(de dia: Date, calendario: Calendar) -> [Date] {
        guard let mes = calendario.dateInterval(of: .month, for: dia),
              let primeira = calendario.dateInterval(of: .weekOfYear, for: mes.start),
              let ultima = calendario.dateInterval(of: .weekOfYear, for: mes.end.addingTimeInterval(-1)) else {
            return semana(de: dia, calendario: calendario)
        }
        let semanas = (calendario.dateComponents([.day], from: primeira.start, to: ultima.start).day ?? 0) / 7 + 1
        return dias(desde: primeira.start, total: semanas * 7, calendario: calendario)
    }

    /// O que ler do EventKit para mostrar `dia`: a grade do mês inteira, que já contém a semana dele.
    static func intervalo(de dia: Date, calendario: Calendar) -> DateInterval {
        let grade = mes(de: dia, calendario: calendario)
        let inicio = grade.first ?? calendario.startOfDay(for: dia)
        let fim = grade.last.flatMap { calendario.date(byAdding: .day, value: 1, to: $0) } ?? inicio
        return DateInterval(start: inicio, end: fim)
    }

    /// As letras dos dias da semana na ordem da grade ("D S T Q Q S S" em pt-BR com o domingo primeiro).
    static func letras(calendario: Calendar) -> [String] {
        let simbolos = calendario.veryShortStandaloneWeekdaySymbols
        let primeiro = calendario.firstWeekday - 1
        return Array(simbolos[primeiro...] + simbolos[..<primeiro])
    }

    /// Os eventos de um dia: os que passam por ele (um de vários dias aparece em cada um), sem os recusados,
    /// os de dia inteiro primeiro. Todos, até os que já acabaram: é a agenda do dia, não o "a seguir".
    static func eventos(_ eventos: [EventoAgenda], em dia: Date, calendario: Calendar) -> [EventoAgenda] {
        let inicio = calendario.startOfDay(for: dia)
        let fim = calendario.date(byAdding: .day, value: 1, to: inicio) ?? inicio.addingTimeInterval(24 * 3600)
        return eventos
            .filter { !$0.recusado && $0.inicio < fim && ($0.fim > inicio || $0.inicio >= inicio) }  // o de duração zero também
            .sorted { ($0.diaInteiro ? 0 : 1, $0.inicio, $0.titulo) < ($1.diaInteiro ? 0 : 1, $1.inicio, $1.titulo) }
    }

    /// O primeiro evento de cada dia que tem algum: o ponto embaixo do dia, com a cor do calendário dele.
    static func pontos(_ eventos: [EventoAgenda], dias: [Date], calendario: Calendar) -> [Date: EventoAgenda] {
        var pontos: [Date: EventoAgenda] = [:]
        for dia in dias {
            pontos[dia] = Self.eventos(eventos, em: dia, calendario: calendario).first
        }
        return pontos
    }

    /// Quantos eventos cabem na lista sem rolagem: com mais que `maximo`, um a menos, e a última linha vira "mais k".
    static func visiveis(_ total: Int, maximo: Int) -> Int {
        total > maximo ? maximo - 1 : total
    }

    private static func dias(desde inicio: Date, total: Int, calendario: Calendar) -> [Date] {
        // O começo de cada dia, e não "início + n dias": num fuso em que a meia-noite não existe no dia do horário de
        // verão (Santiago, Havana), a semana começa à 1 h e os outros dias herdariam a 1 h, sem bater com o dia escolhido.
        (0..<total).compactMap { calendario.date(byAdding: .day, value: $0, to: inicio).map(calendario.startOfDay) }
    }
}

/// O calendário da pessoa na ilha: o próximo evento e os lembretes. Sem permissão, fica vazio e nada quebra.
@MainActor @Observable
final class Agenda {
    enum Acesso: Equatable { case naoPedido, permitido, negado }

    private(set) var proximo: EventoAgenda?
    /// O resto do dia, para a aba "Hoje".
    private(set) var hoje: [EventoAgenda] = []
    /// A reunião chegando, para as asas (`EventoAgenda.naAsa`). Recalculada a cada minuto com o resto.
    private(set) var emBreve: EventoAgenda?
    private(set) var acesso: Acesso = .naoPedido
    /// Os eventos do mês que a agenda expandida está mostrando (`mostrar`). Vazio com ela recolhida.
    private(set) var doPeriodo: [EventoAgenda] = []

    @ObservationIgnored private let mural: Mural
    /// EKEventStore não é Sendable: fica na thread principal, com a Agenda.
    @ObservationIgnored private let loja = EKEventStore()
    @ObservationIgnored private var avisados: Set<String> = []
    @ObservationIgnored private var relogio: Task<Void, Never>?
    @ObservationIgnored private var periodo: DateInterval?

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
    func entrar(_ evento: EventoAgenda? = nil) {
        guard let link = (evento ?? proximo)?.link, EventoAgenda.aceito(link) else { return }
        NSWorkspace.shared.open(link)
    }

    /// A agenda expandiu (ou trocou de mês): lê o período agora e de novo a cada minuto com o resto, até recolher (`nil`).
    func mostrar(_ intervalo: DateInterval?) {
        guard intervalo != periodo else { return }
        periodo = intervalo
        lerPeriodo()
    }

    private func lerPeriodo() {
        var lidos: [EventoAgenda] = []
        if acesso == .permitido, let periodo {
            let predicado = loja.predicateForEvents(withStart: periodo.start, end: periodo.end, calendars: nil)
            lidos = loja.events(matching: predicado).map(EventoAgenda.init)
        }
        if lidos != doPeriodo { doPeriodo = lidos }
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
        // Qualquer evento, não só o `proximo`: com uma reunião começada há 7 min (ainda o "próximo") e outra em 1 min,
        // a asa mostra a que chega.
        // ponytail: recalcula a cada minuto com o resto; a asa entra e sai até 1 min fora da hora exata.
        let chegando = eventos.compactMap { EventoAgenda.naAsa($0, agora: agora) }.min { $0.inicio < $1.inicio }
        if chegando != emBreve { emBreve = chegando }
        let doDia = EventoAgenda.doDia(eventos, agora: agora)
        if doDia != hoje { hoje = doDia }
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
        lerPeriodo()
    }
}
