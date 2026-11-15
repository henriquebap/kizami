import CoreGraphics

/// Onde a ilha fica numa tela. Regra pura, sem AppKit, para testar com as medidas de telas reais.
/// Coordenadas do AppKit: origem embaixo à esquerda, então o topo da tela é `maxY`.
struct Geometria: Equatable {
    /// Espaço de cada lado do notch para o ícone e o contador; o centro é a câmera.
    static let asa: CGFloat = 36
    static let larguraAberta: CGFloat = 380
    /// Altura da lista abaixo do notch, com três linhas.
    static let alturaLista: CGFloat = 124

    let tela: CGRect
    /// Largura 0 em tela sem notch: a ilha vira só as duas asas, sob a barra de menus.
    let notch: CGSize

    init(tela: CGRect, esquerda: CGFloat?, direita: CGFloat?, topoSeguro: CGFloat, barraDeMenus: CGFloat) {
        self.tela = tela
        if let esquerda, let direita, topoSeguro > 0 {
            notch = CGSize(width: tela.width - esquerda - direita, height: topoSeguro)
        } else {
            // Não usar frame.maxY - visibleFrame.maxY: dá 0 com a barra de menus oculta (visto no monitor externo).
            notch = CGSize(width: 0, height: barraDeMenus)
        }
    }

    var temNotch: Bool { notch.width > 0 }
    var compacta: CGSize { CGSize(width: notch.width + 2 * Self.asa, height: notch.height) }
    var aberta: CGSize { CGSize(width: max(Self.larguraAberta, compacta.width), height: notch.height + Self.alturaLista) }

    /// Retângulo de um tamanho preso ao topo da tela, centrado no notch.
    func retangulo(_ tamanho: CGSize) -> CGRect {
        CGRect(x: tela.midX - tamanho.width / 2, y: tela.maxY - tamanho.height, width: tamanho.width, height: tamanho.height)
    }

    /// Área do hover: 4 pt de folga, porque o cursor encostado no topo fica em y == maxY, fora do `contains`.
    func zona(_ tamanho: CGSize) -> CGRect {
        retangulo(tamanho).insetBy(dx: -4, dy: -4)
    }

    /// Onde o cursor abre a ilha: só o notch, que é área morta. As asas ficam sobre a barra de menus,
    /// e abrir por elas cobriria os menus ao lado do notch a cada passada do cursor.
    /// Sem notch, as asas: o meio da barra de menus costuma ficar vazio.
    var gatilho: CGRect {
        temNotch ? retangulo(notch).insetBy(dx: 0, dy: -4) : zona(compacta)
    }
}
