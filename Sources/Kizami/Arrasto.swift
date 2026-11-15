import AppKit

/// Percebe um arquivo sendo arrastado em qualquer app. A ilha fechada ignora o mouse (para não bloquear a barra
/// de menus), então não receberia o arraste sozinha: avisada, ela abre ao chegar no notch e vira destino.
/// Monitor global de mouse não pede permissão; só o de teclado pede (Acessibilidade).
@MainActor
final class Arrasto {
    private let quadro = NSPasteboard(name: .drag)
    private var contagemNoClique = -1
    private var monitores: [Any] = []

    /// `aoMover` roda a cada movimento de um arraste de arquivo, para as ilhas reagirem na hora
    /// em vez de esperar a próxima consulta do cursor.
    init(bandeja: Bandeja, aoMover: @escaping @MainActor () -> Void) {
        let clique = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.anotarClique() }
        }
        let movimento = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let arquivo = self.arrastandoArquivo()
                if arquivo != bandeja.arrastando { bandeja.arrastando = arquivo }
                if arquivo { aoMover() }
            }
        }
        let soltura = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            MainActor.assumeIsolated {
                guard bandeja.arrastando else { return }
                bandeja.arrastando = false
                aoMover()
            }
        }
        monitores = [clique, movimento, soltura].compactMap { $0 }
    }

    private func anotarClique() {
        contagemNoClique = quadro.changeCount
    }

    /// O quadro de arraste guarda o conteúdo do último arraste: só vale se mudou depois deste clique.
    private func arrastandoArquivo() -> Bool {
        quadro.changeCount != contagemNoClique && (quadro.types?.contains(.fileURL) ?? false)
    }
}
