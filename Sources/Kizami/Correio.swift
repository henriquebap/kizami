import AppKit
import Foundation

/// O que a linha de comando pediu.
enum Pedido: Equatable {
    case enviar(Atividade)
    case remover(String)
    case limpar
}

/// Linha de comando: o próprio binário do app, chamado com uma ação, avisa o Kizami que está rodando e sai.
///     Kizami.app/Contents/MacOS/Kizami enviar --titulo "Build pronto" --simbolo hammer --cor verde
enum Comando {
    private static let opcoes: [String: Set<String>] = [
        "enviar": ["titulo", "detalhe", "simbolo", "cor", "id", "expira", "prioridade"],
        "remover": ["id"],
        "limpar": [],
    ]

    static let ajuda = """
        uso: Kizami enviar --titulo TEXTO [--detalhe TEXTO] [--simbolo SF_SYMBOL] [--cor COR] [--id ID] [--expira SEGUNDOS]
                           [--prioridade baixa|normal|alta|urgente]
             Kizami remover --id ID
             Kizami limpar
        cores: \(Atividade.cores.sorted().joined(separator: ", "))
        --expira 0 deixa a atividade na ilha até "remover"; sem --expira, some em \(Int(Atividade.expiraPadrao)) s.
        --prioridade ordena a ilha (a mais alta primeiro); baixa entra sem descer como aviso. Sem ela, normal.
        """

    /// nil quando falta algo ou sobra uma opção desconhecida: um erro de digitação não pode passar calado.
    static func ler(_ argumentos: [String]) -> Pedido? {
        guard let acao = argumentos.first, let aceitas = opcoes[acao] else { return nil }
        var valores: [String: String] = [:]
        var resto = argumentos.dropFirst()
        while let chave = resto.popFirst() {
            let nome = String(chave.dropFirst(2))
            guard chave.hasPrefix("--"), aceitas.contains(nome), let valor = resto.popFirst() else { return nil }
            valores[nome] = valor
        }
        switch acao {
        case "enviar":
            guard let titulo = valores["titulo"] else { return nil }
            var expira: Double?
            if let texto = valores["expira"] {
                guard let numero = Double(texto), numero.isFinite else { return nil }
                expira = numero
            }
            return .enviar(Atividade(id: valores["id"] ?? UUID().uuidString, titulo: titulo, detalhe: valores["detalhe"],
                                     simbolo: valores["simbolo"], cor: valores["cor"], expira: expira,
                                     prioridade: valores["prioridade"]))
        case "remover":
            return valores["id"].map(Pedido.remover)
        default:
            return .limpar
        }
    }

    /// Código de saída do processo.
    static func executar(_ argumentos: [String]) -> Int32 {
        // Chamado por um hook do Claude Code: sai sempre com 0 e sem nada na saída padrão. Um código diferente
        // vira aviso de erro na conversa, e no SessionStart e no UserPromptSubmit o que sai vira contexto do Claude.
        if argumentos.first == "claude" {
            Correio.encaminharHookDoClaude()
            return 0
        }
        guard let pedido = ler(argumentos) else {
            FileHandle.standardError.write(Data((ajuda + "\n").utf8))
            return 2
        }
        Correio.postar(pedido)
        return 0
    }
}

/// Entre processos pelo DistributedNotificationCenter: não precisa de servidor, porta nem permissão.
/// O conteúdo vai em `object` (texto), que continua chegando mesmo quando quem envia está em sandbox.
enum Correio {
    private static let prefixo = "io.github.henriquebap.kizami."
    static let enviar = Notification.Name(prefixo + "enviar")
    static let remover = Notification.Name(prefixo + "remover")
    static let limpar = Notification.Name(prefixo + "limpar")
    static let claude = Notification.Name(prefixo + "claude")

    static func postar(_ pedido: Pedido) {
        let (nome, objeto): (Notification.Name, String?) = switch pedido {
        case .enviar(let atividade): (enviar, (try? JSONEncoder().encode(atividade)).flatMap { String(data: $0, encoding: .utf8) })
        case .remover(let id): (remover, id)
        case .limpar: (limpar, nil)
        }
        DistributedNotificationCenter.default().postNotificationName(nome, object: objeto, userInfo: nil, deliverImmediately: true)
    }

    @MainActor static func ouvir(_ mural: Mural) {
        let centro = DistributedNotificationCenter.default()
        centro.addObserver(forName: enviar, object: nil, queue: .main) { aviso in
            // 4 KB cabem com folga uma atividade inteira; mais que isso nem é decodificado.
            let dados = (aviso.object as? String).flatMap { $0.utf8.count <= 4096 ? Data($0.utf8) : nil }
            MainActor.assumeIsolated {
                guard let dados, let atividade = try? JSONDecoder().decode(Atividade.self, from: dados) else {
                    registro.notice("mensagem descartada: JSON inválido")
                    return
                }
                mural.receber(atividade)
            }
        }
        centro.addObserver(forName: remover, object: nil, queue: .main) { aviso in
            let id = aviso.object as? String
            MainActor.assumeIsolated { if let id { mural.remover(id: id) } }
        }
        centro.addObserver(forName: limpar, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { mural.limpar() }
        }
    }

    /// Lê o JSON do hook na entrada padrão e manda ao app só o id da sessão, a pasta, o evento, o app onde ela roda
    /// e o terminal dela.
    static func encaminharHookDoClaude() {
        let (app, tty) = ancestrais()
        guard isatty(STDIN_FILENO) == 0, let dados = entrada(ate: MensagemClaude.limiteHook),
              let mensagem = MensagemClaude.doHook(dados, app: app, tty: tty),
              let texto = (try? JSONEncoder().encode(mensagem)).flatMap({ String(data: $0, encoding: .utf8) })
        else { return }
        DistributedNotificationCenter.default().postNotificationName(claude, object: texto, userInfo: nil, deliverImmediately: true)
    }

    /// nil se passar do limite: JSON cortado não teria como ser lido.
    private static func entrada(ate limite: Int) -> Data? {
        var dados = Data()
        while dados.count <= limite, let pedaco = try? FileHandle.standardInput.read(upToCount: 1 << 16), !pedaco.isEmpty {
            dados.append(pedaco)
        }
        return dados.count <= limite ? dados : nil
    }

    /// O app onde a sessão roda: sobe pelos processos pais (sh do hook, claude, shell, login, Terminal) até o primeiro
    /// que está dentro de um .app. `Som.caminhoDoApp` pega o .app mais de fora do caminho, então um helper do
    /// VS Code ("Code Helper (Plugin).app" dentro de "Visual Studio Code.app") vira o VS Code.
    /// No caminho, o terminal de controle do primeiro processo que tem um, que é o da aba: o `claude`, o shell e o
    /// login herdam o pty que o Terminal abriu para ela; se o hook rodar numa sessão própria, sem terminal, o `claude`
    /// ainda tem. O app (Terminal, iTerm2) não tem terminal de controle, então o tty nunca vem de cima dele.
    /// Só um app que a pessoa vê e que dá para trazer para frente. O Claude Code do app Claude roda de dentro de um
    /// `claude.app` próprio (em `Application Support/Claude/claude-code/<versão>/…`), que não é um app aberto: parar
    /// nele dava um bundle que o clique na ilha não achava, e nada abria. Subindo mais, chega no Claude.app.
    private static func appAberto(_ bundle: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).contains { $0.activationPolicy == .regular }
    }

    private static func ancestrais() -> (app: String?, tty: String?) {
        var pid = getppid()
        var tty: String?
        for _ in 0..<32 where pid > 1 {
            var info = kinfo_proc()
            var tamanho = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, u_int(mib.count), &info, &tamanho, nil, 0) == 0, tamanho > 0 else { break }
            // Sem terminal (NODEV), o `devname` devolve nil.
            if tty == nil { tty = devname(info.kp_eproc.e_tdev, S_IFCHR).map { String(cString: $0) } }
            var caminho = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &caminho, UInt32(caminho.count)) > 0,
               let app = Som.caminhoDoApp(String(decoding: caminho.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)),
               let bundle = Bundle(path: app)?.bundleIdentifier,
               Self.appAberto(bundle) {
                return (bundle, tty)
            }
            pid = info.kp_eproc.e_ppid
        }
        return (nil, tty)
    }
}
