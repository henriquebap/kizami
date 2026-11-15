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
            Button("Mostrar exemplo") { Kizami.shared.mostrarExemplo() }
            // Qualquer processo pode deixar uma atividade sem prazo: tirar tudo não pode depender da linha de comando.
            Button("Limpar a ilha") { Kizami.shared.mural.limpar() }
            Divider()
            Button("Sair do Kizami") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
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

/// Raiz de composição.
@MainActor
final class Kizami {
    static let shared = Kizami()

    let mural = Mural()
    private var janela: Janela?

    func iniciar() {
        janela = Janela(mural: mural)
        Correio.ouvir(mural)
    }

    func mostrarExemplo() {
        mural.receber(Atividade(id: "exemplo", titulo: String(localized: "Exemplo do Kizami"),
                                detalhe: String(localized: "Passe o mouse para abrir"),
                                simbolo: "sparkles", cor: "laranja", expira: 8))
    }
}
