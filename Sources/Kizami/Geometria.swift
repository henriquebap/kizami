import CoreGraphics

/// Onde a ilha fica numa tela e de que tamanho é em cada estado. Regra pura, sem AppKit,
/// para testar com as medidas de telas reais. Coordenadas do AppKit: o topo da tela é `maxY`.
struct Geometria: Equatable {
    /// Espaço de cada lado do notch para o ícone e o contador; o centro é a câmera.
    static let asa: CGFloat = 34
    /// A curva côncava no topo que funde a ilha com a borda da tela, como no notch de verdade.
    static let orelha: CGFloat = 8
    static let larguraAviso: CGFloat = 300
    static let larguraAberta: CGFloat = 340
    static let alturaLinha: CGFloat = 30
    static let espacoLinha: CGFloat = 4
    static let maximoLinhas = 3
    /// A fileira de arquivos da bandeja, abaixo da lista.
    static let alturaBandeja: CGFloat = 64
    static let espacoSecao: CGFloat = 10
    /// Margem transparente da janela para a sombra da ilha aberta não ser cortada.
    static let sombra: CGFloat = 18

    let tela: CGRect
    /// Largura 0 em tela sem notch: a ilha vira só as duas asas, no topo da tela.
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

    /// Fechada: o notch com uma asa de cada lado.
    var compacta: CGSize { CGSize(width: notch.width + 2 * (Self.asa + Self.orelha), height: notch.height) }

    /// Por alguns segundos depois que uma atividade chega: uma linha com o título abaixo do notch.
    var aviso: CGSize { CGSize(width: max(Self.larguraAviso, compacta.width), height: notch.height + Self.alturaLinha + 6) }

    /// Com o cursor em cima: a lista, com a altura das linhas que existem (até 3), e a bandeja embaixo.
    /// Sem bandeja, sempre ao menos uma linha; só a bandeja, nenhuma.
    func aberta(linhas: Int, bandeja: Bool = false) -> CGSize {
        let n = CGFloat(min(max(linhas, bandeja ? 0 : 1), Self.maximoLinhas))
        let lista = n > 0 ? n * Self.alturaLinha + (n - 1) * Self.espacoLinha : 0
        let fileira = bandeja ? Self.alturaBandeja + (n > 0 ? Self.espacoSecao : 0) : 0
        return CGSize(width: max(Self.larguraAberta, compacta.width), height: notch.height + 8 + lista + fileira + 14)
    }

    /// A janela tem o tamanho do maior estado mais a margem da sombra; a forma anima dentro dela.
    var janela: CGRect {
        let maior = aberta(linhas: Self.maximoLinhas, bandeja: true)
        return retangulo(CGSize(width: maior.width + 2 * Self.sombra, height: maior.height + Self.sombra))
    }

    /// Retângulo de um tamanho preso ao topo da tela, centrado no notch.
    func retangulo(_ tamanho: CGSize) -> CGRect {
        CGRect(x: tela.midX - tamanho.width / 2, y: tela.maxY - tamanho.height, width: tamanho.width, height: tamanho.height)
    }

    /// Área do hover: 4 pt de folga, porque o cursor encostado no topo fica em y == maxY, fora do `contains`.
    func zona(_ tamanho: CGSize) -> CGRect {
        retangulo(tamanho).insetBy(dx: -4, dy: -4)
    }

    /// Onde o cursor abre a ilha fechada: só o notch, que é área morta. As asas ficam sobre a barra de menus,
    /// e abrir por elas cobriria os menus ao lado do notch a cada passada do cursor.
    /// Sem notch, as asas: o meio do topo da tela costuma ficar vazio.
    var gatilho: CGRect {
        temNotch ? retangulo(notch).insetBy(dx: 0, dy: -4) : zona(compacta)
    }
}
