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
            MenuView(mural: Kizami.shared.mural)
        }
    }
}

/// O menu diz o que o Kizami é e o que está na ilha, para não ser um ícone mudo na barra.
private struct MenuView: View {
    let mural: Mural

    var body: some View {
        Text("Kizami está rodando")
        Text(resumo)
        Divider()
        Button("Mostrar exemplo") { Kizami.shared.mostrarExemplo() }
        // Qualquer processo pode deixar uma atividade sem prazo: tirar tudo não pode depender da linha de comando.
        Button("Limpar a ilha") { mural.limpar() }
            .disabled(mural.atividades.isEmpty)
        Divider()
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

/// Raiz de composição: o mural e uma ilha por monitor.
@MainActor
final class Kizami {
    static let shared = Kizami()

    let mural = Mural()
    private var janelas: [Janela] = []

    func iniciar() {
        montarIlhas()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Kizami.shared.montarIlhas() }
        }
        Correio.ouvir(mural)
        // Sinal de vida ao abrir: sem ele, o Kizami começa invisível, escondido atrás do notch.
        mural.receber(Atividade(id: "kizami", titulo: String(localized: "Kizami está rodando"),
                                detalhe: String(localized: "Passe o mouse para abrir"),
                                simbolo: "capsule.tophalf.filled", cor: "laranja", expira: 6))
    }

    /// Uma ilha em cada monitor: a pessoa vê o aviso na tela em que está trabalhando, tenha ela notch ou não.
    private func montarIlhas() {
        janelas.forEach { $0.fechar() }
        janelas = NSScreen.screens.map { Janela(mural: mural, tela: $0) }
        registro.info("ilhas: \(self.janelas.count) monitor(es), \(NSScreen.screens.filter { $0.safeAreaInsets.top > 0 }.count) com notch")
    }

    func mostrarExemplo() {
        mural.receber(Atividade(id: "exemplo", titulo: String(localized: "Exemplo do Kizami"),
                                detalhe: String(localized: "Passe o mouse para abrir"),
                                simbolo: "sparkles", cor: "azul", expira: 8))
    }
}
