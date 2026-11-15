import Foundation
import Observation

/// Arquivos que a pessoa soltou no notch para levar a outro lugar. Guarda o endereço, não uma cópia:
/// arrastar de volta para fora funciona como arrastar do Finder, e nada ocupa espaço em disco.
// ponytail: só em memória, então sair do Kizami esvazia a bandeja. Guardar bookmarks em Application Support
// se a bandeja precisar sobreviver a um reinício.
@MainActor @Observable
final class Bandeja {
    static let maximo = 20

    /// Na ordem em que chegaram; o que passa do máximo sai pelo mais antigo.
    private(set) var arquivos: [URL] = []
    /// Um arquivo está sendo arrastado em algum app: a ilha abre ao chegar no notch para receber.
    var arrastando = false

    var visivel: Bool { arrastando || !arquivos.isEmpty }

    /// Devolve quantos arquivos entraram (0 se nada era arquivo).
    @discardableResult func adicionar(_ urls: [URL]) -> Int {
        var novos: [URL] = []
        for url in urls where url.isFileURL && !novos.contains(url.standardizedFileURL) {
            novos.append(url.standardizedFileURL)
        }
        guard !novos.isEmpty else { return 0 }
        // Soltar de novo um arquivo que já está na bandeja leva ele para o fim, sem duplicar.
        arquivos = Array((arquivos.filter { !novos.contains($0) } + novos).suffix(Self.maximo))
        registro.info("bandeja: \(novos.count) arquivo(s) solto(s), \(self.arquivos.count) no total")
        return novos.count
    }

    func remover(_ url: URL) {
        arquivos = arquivos.filter { $0 != url }
    }

    func esvaziar() {
        arquivos = []
    }

    /// Tira o que foi movido ou apagado desde que entrou na bandeja.
    func podar() {
        let existem = arquivos.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existem.count != arquivos.count { arquivos = existem }
    }
}
