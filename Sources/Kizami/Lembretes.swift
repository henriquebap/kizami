import AppKit
import EventKit
import Observation

/// Um lembrete do app Lembretes, já pronto para a ilha. O título pode ter vindo de uma lista compartilhada:
/// é dado de fora, limpo como o de uma `Atividade` e nunca registrado no log.
struct Lembrete: Equatable, Identifiable, Sendable {
    /// O `calendarItemIdentifier`: é por ele que `Lembretes.concluir` acha o lembrete de novo no EventKit.
    var id: String
    var titulo: String
    /// O prazo. Sem hora (`temHora == false`), é a meia-noite do dia: vale o dia inteiro.
    var vence: Date?
    var temHora = false
    /// A prioridade do EventKit: 0 é nenhuma, 1–4 alta, 5 média, 6–9 baixa.
    var prioridade = 0
    var concluido = false

    static let maximo = 3

    /// Os da ilha: os atrasados e os de hoje primeiro, pelo prazo; depois os sem data, pela prioridade.
    /// Os de amanhã em diante ficam de fora: a ilha é o que dá para fazer hoje, e o Lembretes mostra o resto.
    /// Os sem data entram porque muita gente não põe data em nada; sem eles, a lista ficaria quase sempre vazia.
    static func proximos(_ lembretes: [Lembrete], agora: Date, calendario: Calendar = .current) -> [Lembrete] {
        let inicioDoDia = calendario.startOfDay(for: agora)
        let amanha = calendario.date(byAdding: .day, value: 1, to: inicioDoDia) ?? inicioDoDia.addingTimeInterval(24 * 3600)
        let pendentes = lembretes.filter { !$0.concluido }
        let doDia = pendentes
            .compactMap { l in l.vence.flatMap { $0 < amanha ? (l, $0) : nil } }
            .sorted { ($0.1, $0.0.ordem, $0.0.titulo) < ($1.1, $1.0.ordem, $1.0.titulo) }  // título desempata: não pisca
            .map(\.0)
        let semData = pendentes
            .filter { $0.vence == nil }
            .sorted { ($0.ordem, $0.titulo) < ($1.ordem, $1.titulo) }
        return Array((doDia + semData).prefix(maximo))
    }

    /// Passou do prazo: da hora, se tem hora; do dia, se não tem (vence hoje sem hora ainda não está atrasado).
    func atrasado(agora: Date, calendario: Calendar = .current) -> Bool {
        guard let vence else { return false }
        return temHora ? vence < agora : vence < calendario.startOfDay(for: agora)
    }

    /// O texto curto ao lado do título: "atrasado", a hora ("15:00") ou "hoje". Sem data, nada.
    func quando(agora: Date, calendario: Calendar = .current) -> String? {
        guard let vence else { return nil }
        if atrasado(agora: agora, calendario: calendario) { return String(localized: "atrasado") }
        if temHora { return vence.formatted(date: .omitted, time: .shortened) }
        // ponytail: data-sem-hora de amanhã em diante cai aqui também, mas `proximos` nunca deixa um desses passar.
        return String(localized: "hoje")
    }

    /// Prioridade 0 (nenhuma) por último, e não primeiro, como o número sugeriria.
    private var ordem: Int { prioridade == 0 ? 10 : prioridade }
}

extension Lembrete {
    init(_ lembrete: EKReminder, calendario: Calendar = .current) {
        let titulo = Atividade.limpo(lembrete.title ?? "", ate: 60)
        let prazo = lembrete.dueDateComponents
        self.init(id: lembrete.calendarItemIdentifier,
                  titulo: titulo.isEmpty ? String(localized: "Sem título") : titulo,
                  vence: prazo.flatMap { calendario.date(from: $0) },
                  temHora: prazo?.hour != nil,
                  prioridade: lembrete.priority,
                  concluido: lembrete.isCompleted)
    }
}

/// Os lembretes de hoje na ilha, se a pessoa ligar nos Ajustes. Lê o app Lembretes e só escreve uma coisa:
/// "concluído", no clique da pessoa. Sem permissão, fica vazio e nada quebra.
@MainActor @Observable
final class Lembretes {
    static let chave = "lembretes.ligado"

    enum Acesso: Equatable { case naoPedido, permitido, negado }

    var ligado: Bool {
        didSet {
            guard ligado != oldValue else { return }
            UserDefaults.standard.set(ligado, forKey: Self.chave)
            ligado ? ligar() : parar()
        }
    }
    private(set) var acesso: Acesso = .naoPedido
    /// No máximo 3 (`Lembrete.proximos`). Vazio com a fonte desligada ou sem acesso.
    private(set) var proximos: [Lembrete] = []

    /// Uma loja só dos lembretes, separada da `Agenda`: o acesso é outro e cada uma vive na thread principal.
    @ObservationIgnored private let loja = EKEventStore()
    @ObservationIgnored private var observadores: [NSObjectProtocol] = []
    /// A busca em andamento: uma nova cancela a anterior, para uma resposta velha não sobrescrever uma nova.
    @ObservationIgnored private var busca: Any?

    init() {
        ligado = UserDefaults.standard.bool(forKey: Self.chave)
    }

    /// Na abertura do app e ao abrir os Ajustes (liberado nos Ajustes do Sistema depois de negado).
    func iniciar() {
        if ligado { ligar() }
    }

    /// Pede o acesso na primeira vez e começa a ler. Chamado de novo, só confere o acesso.
    func ligar() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            comecar()
        case .notDetermined:
            // Forte de propósito: a resposta chega uma vez só, e os Lembretes vivem enquanto o app vive.
            loja.requestFullAccessToReminders { permitido, _ in
                Task { @MainActor in
                    if permitido { self.comecar() } else { self.negar() }
                }
            }
        default:  // negado ou restrito
            negar()
        }
    }

    /// Marca como concluído no app Lembretes e tira da lista na hora, sem esperar o EventKit avisar.
    func concluir(_ id: Lembrete.ID) {
        guard acesso == .permitido, let lembrete = loja.calendarItem(withIdentifier: id) as? EKReminder else { return }
        proximos.removeAll { $0.id == id }
        lembrete.isCompleted = true
        do {
            try loja.save(lembrete, commit: true)
        } catch {
            // O erro do EventKit não leva o título; mesmo assim, só o código vai para o log.
            registro.error("lembretes: não deu para concluir (\((error as NSError).code))")
            atualizar()  // devolve o lembrete à lista: ele continua pendente
        }
    }

    private func negar() {
        acesso = .negado
        if !proximos.isEmpty { proximos = [] }
        registro.notice("lembretes: sem acesso aos Lembretes")
    }

    private func comecar() {
        acesso = .permitido
        guard ligado else { return }  // desligado enquanto o macOS perguntava
        if observadores.isEmpty {
            let centro = NotificationCenter.default
            // Muda tanto pelo app Lembretes quanto pelo próprio `concluir`.
            observadores.append(centro.addObserver(forName: .EKEventStoreChanged, object: loja, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.atualizar() }
            })
            // Virando o dia, os de amanhã viram de hoje. O macOS também posta isto ao acordar num dia novo.
            observadores.append(centro.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.atualizar() }
            })
        }
        atualizar()
    }

    private func parar() {
        observadores.forEach(NotificationCenter.default.removeObserver)
        observadores = []
        busca.map(loja.cancelFetchRequest)
        busca = nil
        if !proximos.isEmpty { proximos = [] }
    }

    private func atualizar() {
        guard ligado, acesso == .permitido else { return }
        busca.map(loja.cancelFetchRequest)
        // Só os pendentes: os concluídos podem ser milhares e nunca aparecem.
        let predicado = loja.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        busca = Self.buscar(loja, predicado) { [weak self] lidos in
            Task { @MainActor in self?.receber(lidos) }
        }
    }

    private func receber(_ lidos: [Lembrete]) {
        busca = nil
        guard ligado, acesso == .permitido else { return }
        let novos = Lembrete.proximos(lidos, agora: .now)
        // Energia: só escreve quando o que está na tela muda.
        if novos != proximos { proximos = novos }
        registro.info("lembretes: \(novos.count) na ilha de \(lidos.count) pendentes")
    }

    /// Fora do ator principal de propósito: o EventKit chama de volta numa fila qualquer, e um closure criado aqui
    /// não herda o isolamento do `@MainActor` (que o Swift 6 conferiria na hora, e derrubaria o app).
    /// Os `EKReminder` não são Sendable: viram `Lembrete` ainda na fila do EventKit.
    nonisolated private static func buscar(_ loja: EKEventStore, _ predicado: NSPredicate,
                                           _ pronto: @escaping @Sendable ([Lembrete]) -> Void) -> Any {
        loja.fetchReminders(matching: predicado) { lembretes in
            pronto((lembretes ?? []).map { Lembrete($0) })
        }
    }
}
