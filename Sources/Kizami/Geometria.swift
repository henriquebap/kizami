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
    /// A linha do que está tocando: miniatura, título e artista.
    static let alturaTocando: CGFloat = 52
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

    /// Em repouso, sem nada para mostrar: só um pouco maior que o notch, para a ilha estar sempre à vista.
    /// Sem notch, uma pílula pequena no topo da tela.
    var repouso: CGSize { CGSize(width: max(notch.width + 2 * (Self.orelha + 12), 110), height: notch.height) }

    /// Fechada: o notch com uma asa de cada lado.
    var compacta: CGSize { CGSize(width: notch.width + 2 * (Self.asa + Self.orelha), height: notch.height) }

    /// Por alguns segundos depois que uma atividade chega: uma linha com o título abaixo do notch.
    var aviso: CGSize { CGSize(width: max(Self.larguraAviso, compacta.width), height: notch.height + Self.alturaLinha + 6) }

    /// Com o cursor em cima: as seções que existem, uma embaixo da outra.
    func aberta(_ secoes: Secoes) -> CGSize {
        let n = CGFloat(secoes.linhas)
        let blocos = [
            secoes.tocando ? Self.alturaTocando : 0,
            n > 0 ? n * Self.alturaLinha + (n - 1) * Self.espacoLinha : 0,
            secoes.bandeja ? Self.alturaBandeja : 0,
        ].filter { $0 > 0 }
        let conteudo = blocos.reduce(0, +) + CGFloat(max(blocos.count - 1, 0)) * Self.espacoSecao
        return CGSize(width: max(Self.larguraAberta, compacta.width), height: notch.height + 8 + conteudo + 14)
    }

    /// A janela tem o tamanho do maior estado mais a margem da sombra; a forma anima dentro dela.
    var janela: CGRect {
        let maior = aberta(Secoes(tocando: true, atividades: Self.maximoLinhas, arquivos: 1, arrastando: false))
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
    /// Sem notch, a pílula em repouso: o meio do topo da tela costuma ficar vazio.
    var gatilho: CGRect {
        temNotch ? retangulo(notch).insetBy(dx: 0, dy: -4) : zona(repouso)
    }
}

/// O que a ilha aberta mostra, de cima para baixo. A janela (área do hover) e a view medem com a mesma regra.
struct Secoes: Equatable {
    let tocando: Bool
    let linhas: Int
    let bandeja: Bool

    init(tocando: Bool, atividades: Int, arquivos: Int, arrastando: Bool) {
        self.tocando = tocando
        linhas = min(atividades, Geometria.maximoLinhas)
        // Sem nada para mostrar, a ilha aberta oferece a bandeja vazia: é o que dá para fazer com ela.
        bandeja = arquivos > 0 || arrastando || (atividades == 0 && !tocando)
    }
}
