import AppKit
import Observation

enum EstadoClaude: String, Codable, Sendable {
    case trabalhando, precisaDeVoce, pronta

    /// Ordem na ilha: quem pede atenção primeiro.
    var prioridade: Int {
        switch self {
        case .precisaDeVoce: 0
        case .trabalhando: 1
        case .pronta: 2
        }
    }
}

/// Uma sessão do Claude Code em andamento, como os hooks contam.
struct SessaoClaude: Identifiable, Equatable, Sendable {
    let id: String
    var pasta: String
    var estado: EstadoClaude
    /// Quando entrou no estado atual: é o tempo que a linha mostra.
    var desde: Date
    /// Último evento recebido. Separado de `desde` porque uma sessão trabalhando manda um evento por ferramenta
    /// sem mudar de estado, e o tempo na linha não pode zerar a cada um.
    var visto: Date
    /// Bundle id do app onde a sessão roda (Terminal, VS Code, Claude), para o clique trazê-lo para frente.
    var app: String?
    /// Terminal da sessão (`ttys003`), para o clique achar a aba no Terminal ou no iTerm2. Anda junto com `app`.
    var tty: String?

    static let maximo = 16
    /// Uma sessão pronta e parada há meia hora já não é novidade: ou a pessoa viu, ou foi embora.
    static let prontaExpira: TimeInterval = 30 * 60
    /// Qualquer sessão sem evento por 3 h some: o `SessionEnd` se perde quando o terminal é morto, quando o
    /// Kizami não estava aberto, ou quando o hook passa do prazo de 1,5 s que o Claude Code dá a ele. Uma ferramenta
    /// sozinha raramente roda 3 h; se rodar, o próximo evento traz a sessão de volta.
    static let semSinalExpira: TimeInterval = 3 * 3600
    /// O Esc não dispara o `Stop`, e um pedido de permissão recusado pode não mandar mais nada: sem isto, a sessão
    /// ficaria "trabalhando" ou "precisa de você" (com o aviso preso na ilha) até a pessoa voltar a digitar.
    /// Uma ferramenta longa sem evento também cai para "pronta"; o `PostToolUse` dela traz o "trabalhando" de volta.
    static let trabalhandoSemSinal: TimeInterval = 20 * 60
    static let esperaExpira: TimeInterval = 15 * 60

    /// Aplica um evento à lista e devolve a lista nova, já ordenada e cortada em `maximo`.
    static func aplicar(_ mensagem: MensagemClaude, a sessoes: [SessaoClaude], agora: Date) -> [SessaoClaude] {
        let antiga = sessoes.first { $0.id == mensagem.id }
        let resto = sessoes.filter { $0.id != mensagem.id }
        let estado: EstadoClaude
        switch mensagem.evento {
        case .fim: return resto
        // SessionStart também chega no meio do trabalho (compactação automática): não muda o estado de quem já existe.
        case .inicio: estado = antiga?.estado ?? .pronta
        // Ferramenta de um subagente: só tira do "precisa de você" (a permissão foi respondida). Não liga o
        // "trabalhando", porque um subagente em segundo plano continua depois do Stop da sessão.
        case .subagente: estado = antiga.map { $0.estado == .precisaDeVoce ? .trabalhando : $0.estado } ?? .trabalhando
        case .trabalhando: estado = .trabalhando
        case .precisaDeVoce: estado = .precisaDeVoce
        case .pronta: estado = .pronta
        }
        let desde = antiga.flatMap { $0.estado == estado ? $0.desde : nil } ?? agora
        // O tty vale para o app com que veio: um evento sem app (o caminho até ele falhou) fica com o par antigo.
        let (app, tty) = mensagem.app != nil ? (mensagem.app, mensagem.tty) : (antiga?.app, antiga?.tty)
        let nova = SessaoClaude(id: mensagem.id, pasta: mensagem.pasta, estado: estado, desde: desde, visto: agora,
                                app: app, tty: tty)
        return Array(ordenadas(resto + [nova]).prefix(maximo))
    }

    /// "Precisa de você" primeiro, depois trabalhando, depois prontas; dentro de cada, a mais recente primeiro.
    static func ordenadas(_ sessoes: [SessaoClaude]) -> [SessaoClaude] {
        sessoes.sorted {
            ($0.estado.prioridade, -$0.desde.timeIntervalSinceReferenceDate, $0.id)
                < ($1.estado.prioridade, -$1.desde.timeIntervalSinceReferenceDate, $1.id)
        }
    }

    /// Sem sinal por muito tempo, "trabalhando" e "precisa de você" viram "pronta" (a partir de agora).
    static func envelhecidas(_ sessoes: [SessaoClaude], agora: Date) -> [SessaoClaude] {
        sessoes.map { s in
            let parada = switch s.estado {
            case .trabalhando: agora.timeIntervalSince(s.visto) > trabalhandoSemSinal
            case .precisaDeVoce: agora.timeIntervalSince(s.desde) > esperaExpira
            case .pronta: false
            }
            guard parada else { return s }
            var pronta = s
            pronta.estado = .pronta
            pronta.desde = agora
            return pronta
        }
    }

    static func vivas(_ sessoes: [SessaoClaude], agora: Date) -> [SessaoClaude] {
        sessoes.filter {
            agora.timeIntervalSince($0.visto) <= semSinalExpira
                && !($0.estado == .pronta && agora.timeIntervalSince($0.desde) > prontaExpira)
        }
    }
}

/// O que `Kizami claude` manda ao app. Só o id da sessão, o nome da pasta, o evento, o app e o terminal atravessam:
/// nunca o prompt, a resposta nem o texto da notificação.
struct MensagemClaude: Codable, Equatable, Sendable {
    enum Evento: String, Codable, Sendable {
        case inicio, trabalhando, precisaDeVoce, pronta, subagente, fim
    }

    var id: String
    var pasta: String
    var evento: Evento
    var app: String?
    var tty: String?

    /// O mesmo teto do `Correio`: uma mensagem inteira cabe com folga.
    static let limite = 4096
    /// Teto do JSON do hook na entrada padrão. Não dá para ser pequeno: o `Stop` traz a última resposta inteira
    /// e o `PostToolUse` a saída da ferramenta, que passam de 64 KB com facilidade; cortar perderia o `Stop` e a
    /// sessão ficaria "trabalhando". Acima disso o evento se perde, e o próximo corrige o estado.
    static let limiteHook = 4 << 20

    /// Lê o JSON de um hook do Claude Code (https://code.claude.com/docs/en/hooks).
    /// nil para evento que a ilha não mostra, JSON inválido ou campo faltando.
    static func doHook(_ dados: Data, app: String?, tty: String? = nil) -> MensagemClaude? {
        guard dados.count <= limiteHook,
              let json = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any],
              let id = json["session_id"] as? String,
              let cwd = json["cwd"] as? String,
              let nome = json["hook_event_name"] as? String,
              let evento = evento(nome, notificacao: json["notification_type"] as? String,
                                  subagente: json["agent_id"] as? String != nil)
        else { return nil }
        return validar(MensagemClaude(id: id, pasta: (cwd as NSString).lastPathComponent, evento: evento, app: app, tty: tty))
    }

    static func evento(_ nome: String, notificacao: String?, subagente: Bool) -> Evento? {
        switch nome {
        case "SessionStart": .inicio
        case "UserPromptSubmit": .trabalhando
        case "PreToolUse", "PostToolUse", "PostToolUseFailure": subagente ? .subagente : .trabalhando
        case "Notification":
            switch notificacao {
            // Os três param a sessão esperando uma resposta da pessoa.
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog": .precisaDeVoce
            case "idle_prompt": .pronta
            default: nil
            }
        // StopFailure: o turno acabou por erro da API; a sessão espera a pessoa do mesmo jeito.
        case "Stop", "StopFailure": .pronta
        case "SessionEnd": .fim
        default: nil
        }
    }

    /// A única porta de entrada no app: qualquer processo do Mac pode postar a notificação.
    static func ler(_ objeto: String?) -> MensagemClaude? {
        guard let objeto, objeto.utf8.count <= limite,
              let mensagem = try? JSONDecoder().decode(MensagemClaude.self, from: Data(objeto.utf8))
        else { return nil }
        return validar(mensagem)
    }

    /// O id vira parte do id de uma `Atividade` (64 escalares no máximo, com o prefixo "claude-fim-"):
    /// cortar faria duas sessões colidirem, então id longo ou estranho é recusado. O id real é um UUID.
    static func validar(_ bruta: MensagemClaude) -> MensagemClaude? {
        let pasta = Atividade.limpo(bruta.pasta, ate: 40)
        guard (1...48).contains(bruta.id.utf8.count), bruta.id.unicodeScalars.allSatisfy(idValido), !pasta.isEmpty else {
            return nil
        }
        let app = bruta.app.flatMap { (1...155).contains($0.utf8.count) && $0.unicodeScalars.allSatisfy(bundleValido) ? $0 : nil }
        return MensagemClaude(id: bruta.id, pasta: pasta, evento: bruta.evento, app: app, tty: bruta.tty.flatMap { ttyValido($0) ? $0 : nil })
    }

    /// Só o nome de um pseudoterminal: ele entra num AppleScript, e qualquer processo pode postar a notificação.
    static func ttyValido(_ tty: String) -> Bool {
        tty.wholeMatch(of: /ttys[0-9]{1,4}/) != nil
    }

    private static func idValido(_ c: Unicode.Scalar) -> Bool {
        c.isASCII && (c.properties.isAlphabetic || c.properties.numericType != nil || c == "-" || c == "_")
    }

    private static func bundleValido(_ c: Unicode.Scalar) -> Bool {
        c.isASCII && (c.properties.isAlphabetic || c.properties.numericType != nil || c == "-" || c == ".")
    }
}

/// As sessões na ilha. Os avisos no `Mural` saem das mudanças de estado, não dos eventos: um `permission_prompt`
/// repetido não pisca a ilha de novo.
@MainActor @Observable
final class SessoesClaude {
    private(set) var sessoes: [SessaoClaude] = []
    @ObservationIgnored private let mural: Mural
    @ObservationIgnored private var varredura: Task<Void, Never>?
    /// Sessões que acabaram há pouco. Os hooks são assíncronos, cada um num processo: um `Stop` atrasado pode chegar
    /// depois do `SessionEnd` e recriaria a sessão como fantasma.
    @ObservationIgnored private var encerradas: [String: Date] = [:]
    private static let lutoDeEncerrada: TimeInterval = 60

    init(mural: Mural) {
        self.mural = mural
    }

    func iniciar() {
        guard varredura == nil else { return }
        DistributedNotificationCenter.default().addObserver(forName: Correio.claude, object: nil, queue: .main) { [weak self] aviso in
            let objeto = aviso.object as? String
            MainActor.assumeIsolated {
                guard let mensagem = MensagemClaude.ler(objeto) else {
                    registro.notice("claude: mensagem descartada")
                    return
                }
                self?.receber(mensagem)
            }
        }
        varredura = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.varrer(agora: .now)
            }
        }
    }

    func receber(_ mensagem: MensagemClaude, agora: Date = .now) {
        encerradas = encerradas.filter { agora.timeIntervalSince($0.value) < Self.lutoDeEncerrada }
        if mensagem.evento == .fim {
            encerradas[mensagem.id] = agora
        } else if mensagem.evento != .inicio, encerradas[mensagem.id] != nil {
            return  // atrasado; um `inicio` com o mesmo id é um --resume e vale
        }
        trocar(por: SessaoClaude.aplicar(mensagem, a: sessoes, agora: agora))
    }

    func varrer(agora: Date) {
        let novas = SessaoClaude.vivas(SessaoClaude.envelhecidas(sessoes, agora: agora), agora: agora)
        // Pela varredura não houve Stop: nada de "Claude terminou".
        if novas != sessoes { trocar(por: novas, avisarFim: false) }
    }

    /// Traz para frente o app da sessão e, no Terminal e no iTerm2, a aba dela. É o clique da pessoa que pede;
    /// o Kizami continua sem foco.
    // ponytail: no VS Code, em outro editor e no app Claude, só o app vem para frente. O app Claude não documenta
    // link para uma sessão existente do Claude Code (só `claude://code/new`); o `vscode://anthropic.claude-code/open?session=`
    // documentado abre na janela que estiver em foco e, se a sessão não for da pasta dela, começa uma conversa nova.
    // Trocar quando houver um link documentado que ache a janela certa sozinho.
    func focar(_ sessao: SessaoClaude) {
        guard let bundle = sessao.app,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            registro.notice("claude: app da sessão não está aberto")
            return
        }
        guard let tty = sessao.tty, let script = AbaDoTerminal.script(app: bundle, tty: tty) else {
            Self.ativar(app)
            return
        }
        // A aba antes da ativação: o app já chega com a janela certa na frente. Automação negada, aba fechada ou
        // script com erro dão em nil ou "", e fica a ativação do app, como antes.
        Task {
            if await AppleScript.rodar(script) != "ok" { registro.info("claude: aba da sessão não encontrada") }
            Self.ativar(app)
        }
    }

    private static func ativar(_ app: NSRunningApplication) {
        // A ativação cooperativa (macOS 14+) pode recusar o pedido de um app que não está ativo;
        // pelo Launch Services, abrir um app que já roda só o traz para frente.
        if !app.activate(), let url = app.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    private func trocar(por novas: [SessaoClaude], avisarFim: Bool = true) {
        let antes = Dictionary(sessoes.map { ($0.id, $0.estado) }, uniquingKeysWith: { a, _ in a })
        let depois = Dictionary(novas.map { ($0.id, $0.estado) }, uniquingKeysWith: { a, _ in a })
        sessoes = novas
        guard antes != depois else { return }
        registro.info("claude: \(novas.count) sessão(ões), \(novas.filter { $0.estado == .precisaDeVoce }.count) esperando")
        for (id, estado) in antes where estado == .precisaDeVoce && depois[id] != .precisaDeVoce {
            mural.remover(id: "claude-\(id)")
        }
        for sessao in novas where sessao.estado != antes[sessao.id] {
            switch sessao.estado {
            case .precisaDeVoce:
                mural.receber(Atividade(id: "claude-\(sessao.id)", titulo: String(localized: "Claude precisa de você"),
                                        detalhe: sessao.pasta, simbolo: "exclamationmark.bubble.fill", cor: "laranja", expira: 0,
                                        prioridade: "urgente")) { [weak self] in self?.focar(sessao) }
            case .pronta where avisarFim && antes[sessao.id] == .trabalhando:
                mural.receber(Atividade(id: "claude-fim-\(sessao.id)", titulo: String(localized: "Claude terminou"),
                                        detalhe: sessao.pasta, simbolo: "checkmark.circle.fill", cor: "verde", expira: 6)) { [weak self] in self?.focar(sessao) }
            default:
                break
            }
        }
    }
}

/// O AppleScript que seleciona a aba do Terminal ou a sessão do iTerm2 cujo `tty` é o da sessão do Claude e põe a
/// janela dela na frente das outras do app. Pede Automação para o Terminal ou o iTerm2 na primeira vez.
/// O único texto de fora no script é o tty, conferido aqui de novo: o resto é fixo.
enum AbaDoTerminal {
    static let terminal = "com.apple.Terminal"
    static let iterm = "com.googlecode.iterm2"

    /// nil para outro app ou tty inválido. Pelo bundle id, não pelo nome: o iTerm2 se chama "iTerm" no disco.
    /// O `is running` vem antes do `tell`: falar com um app fechado abriria o app.
    static func script(app: String, tty: String) -> String? {
        guard MensagemClaude.ttyValido(tty) else { return nil }
        let dispositivo = "/dev/" + tty
        switch app {
        case terminal:
            // Abas nativas do macOS aparecem aqui como janelas de uma aba só: pôr a janela na frente já escolhe a aba.
            return """
                if application id "\(terminal)" is not running then return ""
                tell application id "\(terminal)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is "\(dispositivo)" then
                                set miniaturized of w to false
                                set selected tab of w to t
                                set index of w to 1
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end tell
                return ""
                """
        case iterm:
            return """
                if application id "\(iterm)" is not running then return ""
                tell application id "\(iterm)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                if tty of s is "\(dispositivo)" then
                                    select t
                                    select s
                                    select w
                                    return "ok"
                                end if
                            end repeat
                        end repeat
                    end repeat
                end tell
                return ""
                """
        default:
            return nil
        }
    }
}
