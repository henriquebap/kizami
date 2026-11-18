import AppKit

/// A cor da capa como destaque sobre o preto. Arredonda em 3 casas: as contas são em ponto flutuante.
@MainActor func testarDestaque() {
    func destaque(_ r: Double, _ g: Double, _ b: Double) -> [Double]? {
        Capa.destaque(SIMD3(r, g, b)).map { [$0.x, $0.y, $0.z].map { ($0 * 1000).rounded() / 1000 } }
    }
    conferir("cinza não tinge", destaque(0.5, 0.5, 0.5), nil)
    conferir("preto não tinge", destaque(0, 0, 0), nil)
    conferir("escura com matiz de ruído não tinge", destaque(0.08, 0.05, 0.05), nil)
    conferir("vermelho puro: saturação limitada", destaque(1, 0, 0), [1, 0.3, 0.3])
    conferir("verde neon: saturação limitada", destaque(0, 1, 0), [0.3, 1, 0.3])
    conferir("azul escuro: brilho sobe, matiz fica", destaque(0, 0, 0.4), [0.225, 0.225, 0.75])
    conferir("cor já boa não muda", destaque(1, 0.5, 0.5), [1, 0.5, 0.5])
    conferir("pouco saturada ganha um mínimo de cor", destaque(0.8, 0.7, 0.7), [0.8, 0.56, 0.56])

    // Metade vermelha, metade azul: a média é o roxo do meio.
    let capa = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in
        NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 32, height: 64).fill()
        NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(x: 32, y: 0, width: 32, height: 64).fill()
        return true
    }
    conferir("média da capa", Capa.media(capa).map { [$0.x, $0.y, $0.z].map { ($0 * 10).rounded() / 10 } }, [0.5, 0, 0.5])
}
