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
        Settings {
            AjustesView(tempo: Kizami.shared.tempo, agenda: Kizami.shared.agenda, formulario: Kizami.shared.formulario)
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
        SettingsLink { Text("Ajustes…") }
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
    let tempo = Tempo()
    let claude: SessoesClaude
    let formulario = FormularioAjustes()
    private var fontes: Fontes { Fontes(mural: mural, bandeja: bandeja, tocando: tocando, agenda: agenda, tempo: tempo, claude: claude) }
    private var janelas: [Janela] = []
    private var arrasto: Arrasto?

    private init() {
        agenda = Agenda(mural: mural)
        claude = SessoesClaude(mural: mural)
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
        Correio.ouvir(mural)
        tocando.iniciar()
        tempo.iniciar()
        claude.iniciar()
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
        registro.info("ilhas: \(self.janelas.count) monitor(es), \(NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }.count) com notch")
    }

    func mostrarExemplo() {
        mural.receber(Atividade(id: "exemplo", titulo: String(localized: "Exemplo do Kizami"),
                                detalhe: String(localized: "Passe o mouse para abrir"),
                                simbolo: "sparkles", cor: "azul", expira: 8))
    }
}
