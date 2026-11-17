import SwiftUI

/// O mesmo binário é o app e a linha de comando: com argumentos, avisa o app que está rodando e sai.
/// Qualquer argumento vai para a linha de comando (um erro de digitação mostra a ajuda),
/// para um script nunca abrir uma segunda ilha por engano. Aberto pelo Finder ou pelo `open`, não há argumento.
@main
enum Entrada {
    static func main() {
        let argumentos = Array(CommandLine.arguments.dropFirst())
        guard argumentos.isEmpty else { exit(Comando.executar(argumentos)) }
        KizamiApp.main()
    }
}

struct KizamiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Kizami", systemImage: "capsule.tophalf.filled") {
            MenuView(mural: Kizami.shared.mural, bandeja: Kizami.shared.bandeja)
        }
    }
}

/// O menu diz o que o Kizami é e o que está na ilha, para não ser um ícone mudo na barra.
private struct MenuView: View {
    let mural: Mural
    let bandeja: Bandeja

    var body: some View {
        Text("Kizami está rodando")
        Text(resumo)
        Text(resumoDaBandeja)
        Divider()
        Button("Mostrar exemplo") { Kizami.shared.mostrarExemplo() }
        // Qualquer processo pode deixar uma atividade sem prazo: tirar tudo não pode depender da linha de comando.
        Button("Limpar a ilha") { mural.limpar() }
            .disabled(mural.atividades.isEmpty)
        Button("Esvaziar a bandeja") { bandeja.esvaziar() }
            .disabled(bandeja.arquivos.isEmpty)
        Divider()
        Button("Ajustes…") { Kizami.shared.abrirAjustes() }
            .keyboardShortcut(",")
        Button("Sair do Kizami") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var resumo: String {
        switch mural.atividades.count {
        case 0: String(localized: "Nenhuma atividade na ilha")
        case 1: String(localized: "1 atividade na ilha")
        case let n: String(localized: "\(n) atividades na ilha")
        }
    }

    private var resumoDaBandeja: String {
        switch bandeja.arquivos.count {
        case 0: String(localized: "Bandeja vazia: arraste arquivos até o notch")
        case 1: String(localized: "1 arquivo na bandeja")
        case let n: String(localized: "\(n) arquivos na bandeja")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Executado direto (sem o LaunchServices), o app não é instância única: duas ilhas tratariam cada mensagem duas vezes.
        let outras = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        guard !outras.contains(where: { $0 != .current }) else {
            registro.notice("outro Kizami já está aberto: saindo")
            NSApp.terminate(nil)
            return
        }
        Kizami.shared.iniciar()
    }
}

/// Raiz de composição: o mural, a bandeja, o que está tocando e uma ilha por monitor.
@MainActor
final class Kizami {
    static let shared = Kizami()

    let mural = Mural()
    let bandeja = Bandeja()
    let tocando = TocandoAgora()
    let agenda: Agenda
    let tempo: Tempo
    let claude: SessoesClaude
    let mac: Mac
    let interesses: Interesses
    let kanji: PonteKanji
    let cronometro: Cronometro
    let copiados = Copiados()
    let espelho = Espelho()
    let personalizacao = Personalizacao()
    let atalhosApple: AtalhosApple
    let login = Login()
    let downloads: Downloads
    let github: GitHub
    let lembretes = Lembretes()
    let formulario = FormularioAjustes()
    let formularioInteresses = FormularioInteresses()
    private var fontes: Fontes { Fontes(mural: mural, bandeja: bandeja, tocando: tocando, agenda: agenda, tempo: tempo, claude: claude, mac: mac,
                                       interesses: interesses, kanji: kanji, cronometro: cronometro,
                                       copiados: copiados, espelho: espelho,
                                       personalizacao: personalizacao, atalhosApple: atalhosApple) }
    private var janelas: [Janela] = []
    private var ajustes: NSWindow?
    private var arrasto: Arrasto?

    private init() {
        agenda = Agenda(mural: mural)
        tempo = Tempo(mural: mural)
        claude = SessoesClaude(mural: mural)
        mac = Mac(mural: mural)
        interesses = Interesses(mural: mural)
        kanji = PonteKanji(mural: mural)
        cronometro = Cronometro(mural: mural)
        downloads = Downloads(mural: mural)
        github = GitHub(mural: mural)
        atalhosApple = AtalhosApple(mural: mural)
    }

    func iniciar() {
        // Sem janela comum, o macOS trata o app como ocioso e pode encerrá-lo sozinho (visto no log:
        // _kLSApplicationWouldBeTerminatedByTALKey=1). A ilha precisa ficar viva enquanto o app está aberto.
        ProcessInfo.processInfo.disableAutomaticTermination("ilha no notch")
        ProcessInfo.processInfo.disableSuddenTermination()
        montarIlhas()
        arrasto = Arrasto(bandeja: bandeja) { Kizami.shared.janelas.forEach { $0.conferir() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Kizami.shared.montarIlhas() }
        }
        // Entrar e sair de tela cheia troca o espaço ativo. A lista de janelas só se acerta depois da animação,
        // por isso confere de novo um pouco depois.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Kizami.shared.conferirTelaCheia(depois: [0, 0.4, 1.2]) }
        }
        for nome in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: nome, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Kizami.shared.conferirTelaCheia(depois: [0.4, 1.2, 3]) }
            }
        }
        Correio.ouvir(mural)
        tocando.iniciar()
        tempo.iniciar()
        claude.iniciar()
        mac.iniciar()
        interesses.iniciar()
        downloads.iniciar()  // só olha a pasta Downloads se a pessoa ligou nos Ajustes
        github.iniciar()  // só chama o gh se a pessoa ligou nos Ajustes
        lembretes.iniciar()  // só lê o app Lembretes se a pessoa ligou nos Ajustes
        copiados.iniciar()  // só vigia a área de transferência se a pessoa ligou nos Ajustes
        agenda.iniciar()  // por último: na primeira vez, o macOS pergunta pelo acesso aos Calendários
        // Sinal de vida ao abrir: diz o que é a ilha que acabou de aparecer.
        mural.receber(Atividade(id: "kizami", titulo: String(localized: "Kizami está rodando"),
                                detalhe: String(localized: "Passe o mouse para abrir"),
                                simbolo: "capsule.tophalf.filled", cor: "laranja", expira: 6))
    }

    /// Uma ilha em cada monitor: a pessoa vê o aviso na tela em que está trabalhando, tenha ela notch ou não.
    private func montarIlhas() {
        janelas.forEach { $0.fechar() }
        janelas = NSScreen.screens.map { Janela(fontes: fontes, tela: $0) }
        // Monitor novo ou Mac acordando: o papel de parede do monitor chega depois da notificação.
        conferirTelaCheia(depois: [0, 0.4, 1.2, 3])
        registro.info("ilhas: \(self.janelas.count) monitor(es), \(NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }.count) com notch")
    }

    // ponytail: confere só quando o espaço muda. Um app que cobre a tela sem trocar de espaço (o modo antigo de tela
    // cheia, sem animação) não esconde a ilha; conferir também na troca de app ativo se aparecer.
    private func conferirTelaCheia(depois atrasos: [Double]) {
        for atraso in atrasos {
            DispatchQueue.main.asyncAfter(deadline: .now() + atraso) {
                MainActor.assumeIsolated {
                    let (fundos, mesa) = Self.fundosDaMesa()
                    Kizami.shared.janelas.forEach { $0.ajustar(fundos: fundos, mesa: mesa) }
                }
            }
        }
    }

    /// O papel de parede e a mesa do Finder à vista, em coordenadas do Quartz, e se essas janelas existem (à vista
    /// ou não). Dono e camada vêm sem a permissão de Gravação de Tela (só o nome das janelas pede).
    nonisolated private static func fundosDaMesa() -> (fundos: [CGRect], mesa: Bool) {
        let janelas = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let nivel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let doFundo = janelas.filter { janela in
            guard let dono = janela[kCGWindowOwnerName as String] as? String, dono == "Wallpaper" || dono == "Finder",
                  let camada = janela[kCGWindowLayer as String] as? Int else { return false }
            return camada <= nivel
        }
        let fundos = doFundo.compactMap { janela -> CGRect? in
            guard janela[kCGWindowIsOnscreen as String] as? Bool == true,
                  let limites = janela[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: limites)
        }
        return (fundos, !doFundo.isEmpty)
    }

    /// A janela de Ajustes, aberta pelo menu ou pela engrenagem da ilha. Janela própria em vez da cena `Settings`:
    /// o `SettingsLink` só funciona dentro das cenas do SwiftUI, e a ilha é um `NSHostingView` num painel.
    func abrirAjustes() {
        if ajustes == nil {
            let raiz = AjustesView(tempo: tempo, agenda: agenda, mac: mac, interesses: interesses, formulario: formulario,
                                   formularioInteresses: formularioInteresses, copiados: copiados,
                                   downloads: downloads, github: github, lembretes: lembretes,
                                   personalizacao: personalizacao, atalhosApple: atalhosApple, login: login)
            let janela = NSWindow(contentViewController: NSHostingController(rootView: raiz))
            janela.title = String(localized: "Ajustes do Kizami")
            janela.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            janela.isReleasedWhenClosed = false
            janela.center()
            ajustes = janela
        }
        // App sem Dock (LSUIElement): sem ativar, a janela abre atrás do app em que a pessoa está.
        // É a pessoa que pediu a janela; a ilha continua sem nunca tomar o foco.
        NSApp.activate()
        ajustes?.makeKeyAndOrderFront(nil)
        agenda.iniciar()  // liberado nos Ajustes do Sistema depois de negado: confere de novo a cada abertura
        lembretes.iniciar()
        mac.conferirAcesso()
    }

    func mostrarExemplo() {
        mural.receber(Atividade(id: "exemplo", titulo: String(localized: "Exemplo do Kizami"),
                                detalhe: String(localized: "Passe o mouse para abrir"),
                                simbolo: "sparkles", cor: "azul", expira: 8))
    }
}
