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
    /// A faixa de cima da ilha aberta: o próximo evento à esquerda, o tempo à direita.
    static let alturaHoje: CGFloat = 40
    /// O topo da ilha aberta: as abas (Início, Atalhos) e a engrenagem dos Ajustes.
    static let alturaCabecalho: CGFloat = 26
    /// A fileira de atalhos: ícone, nome e teclas.
    static let alturaAtalhos: CGFloat = 62
    /// Sessões do Claude na ilha aberta, uma por linha (`alturaLinha`), as que mais pedem atenção primeiro.
    static let maximoSessoes = 3
    /// Altura mínima da ilha em tela sem notch. Com a altura da barra de menus (22 pt), a capa de 20 pt ficava
    /// encostada em cima e embaixo; lá não há câmera nem barra para respeitar no meio do topo.
    static let alturaSemNotch: CGFloat = 30
    /// Margem transparente da janela para a sombra da ilha aberta não ser cortada.
    static let sombra: CGFloat = 18

    let tela: CGRect
    /// Largura 0 em tela sem notch: a ilha vira só as duas asas, no topo da tela, com `alturaSemNotch`.
    let notch: CGSize

    init(tela: CGRect, esquerda: CGFloat?, direita: CGFloat?, topoSeguro: CGFloat, barraDeMenus: CGFloat) {
        self.tela = tela
        if let esquerda, let direita, topoSeguro > 0 {
            notch = CGSize(width: tela.width - esquerda - direita, height: topoSeguro)
        } else {
            // Não usar frame.maxY - visibleFrame.maxY: dá 0 com a barra de menus oculta (visto no monitor externo).
            notch = CGSize(width: 0, height: max(barraDeMenus, Self.alturaSemNotch))
        }
    }

    var temNotch: Bool { notch.width > 0 }

    /// Onde o conteúdo da ilha aberta começa. Com notch, abaixo dele (é a câmera); sem notch, quase no topo.
    var faixaDoTopo: CGFloat { temNotch ? notch.height : 4 }

    /// Em repouso, sem nada para mostrar: só um pouco maior que o notch, para a ilha estar sempre à vista.
    /// Sem notch, uma pílula pequena no topo da tela.
    var repouso: CGSize { CGSize(width: max(notch.width + 2 * (Self.orelha + 12), 110), height: notch.height) }

    /// Fechada: o notch com uma asa de cada lado. Sem notch, as asas sozinhas dariam 84 pt, mais estreito que
    /// o repouso: a ilha encolheria ao começar a tocar, e a capa ficaria colada nas barras.
    var compacta: CGSize { compacta(icones: 1) }

    /// Fechada com até três atividades: cada ícone a mais alarga as duas asas por igual, para a ilha seguir
    /// centrada no notch (à esquerda os ícones, à direita o contador).
    func compacta(icones: Int) -> CGSize {
        let extra = CGFloat(min(max(icones, 1), 3) - 1) * Self.iconeExtra
        return CGSize(width: max(notch.width + 2 * (Self.asa + extra + Self.orelha), 140 + 2 * extra), height: notch.height)
    }

    /// O que cada ícone a mais ocupa numa asa: o ícone de 20 pt e o espaço entre eles.
    static let iconeExtra: CGFloat = 22

    /// Por alguns segundos depois que uma atividade chega: uma linha com o título abaixo do notch.
    var aviso: CGSize { aviso(linhas: 1) }

    /// Várias chegaram juntas: uma linha para cada, até três.
    func aviso(linhas: Int) -> CGSize {
        let n = CGFloat(min(max(linhas, 1), 3))
        return CGSize(width: max(Self.larguraAviso, compacta.width),
                      height: faixaDoTopo + n * Self.alturaLinha + (n - 1) * Self.espacoLinha + 6)
    }

    /// Com o cursor em cima: as seções que existem, uma embaixo da outra.
    func aberta(_ secoes: Secoes) -> CGSize {
        func linhas(_ n: Int) -> CGFloat { n > 0 ? CGFloat(n) * Self.alturaLinha + CGFloat(n - 1) * Self.espacoLinha : 0 }
        let blocos = [
            Self.alturaCabecalho,
            secoes.hoje ? Self.alturaHoje : 0,
            secoes.interesse ? Self.alturaLinha + 4 : 0,
            linhas(secoes.sessoes),
            secoes.tocando ? Self.alturaTocando : 0,
            linhas(secoes.linhas),
            secoes.apps ? Self.alturaLinha : 0,
            secoes.bandeja ? Self.alturaBandeja : 0,
        ].filter { $0 > 0 }
        let conteudo = blocos.reduce(0, +) + CGFloat(max(blocos.count - 1, 0)) * Self.espacoSecao
        return CGSize(width: max(Self.larguraAberta, compacta.width), height: faixaDoTopo + 8 + conteudo + 14)
    }

    /// A aba de atalhos: o cabeçalho e a fileira.
    var abertaAtalhos: CGSize { abertaComAba(Self.alturaAtalhos) }

    /// A aba do Kanji: a fileira das ações e, com skills, a fileira delas (44 pt) logo abaixo.
    static func alturaKanji(skills: Int) -> CGFloat { alturaAtalhos + (skills > 0 ? 6 + 44 : 0) }

    /// Uma aba que não é o Início: o cabeçalho e o conteúdo dela (atalhos, Kanji).
    func abertaComAba(_ conteudo: CGFloat) -> CGSize {
        CGSize(width: max(Self.larguraAberta, compacta.width),
               height: faixaDoTopo + 8 + Self.alturaCabecalho + Self.espacoSecao + conteudo + 14)
    }

    /// A janela tem o tamanho do maior estado mais a margem da sombra; a forma anima dentro dela.
    var janela: CGRect {
        let maior = aberta(Secoes(tocando: true, atividades: Self.maximoLinhas, arquivos: 1, arrastando: false,
                                  sessoes: Self.maximoSessoes, hoje: true, apps: true, interesse: true))
        // A fechada com três ícones passa da aberta num notch mais largo que ~204 pt.
        let largura = max(maior.width, compacta(icones: 3).width, aviso(linhas: 3).width)
        return retangulo(CGSize(width: largura + 2 * Self.sombra, height: maior.height + Self.sombra))
    }

    /// Retângulo de um tamanho preso ao topo da tela, centrado no notch.
    func retangulo(_ tamanho: CGSize) -> CGRect {
        CGRect(x: tela.midX - tamanho.width / 2, y: tela.maxY - tamanho.height, width: tamanho.width, height: tamanho.height)
    }

    /// Área do hover: 4 pt de folga, porque o cursor encostado no topo fica em y == maxY, fora do `contains`.
    func zona(_ tamanho: CGSize) -> CGRect {
        retangulo(tamanho).insetBy(dx: -4, dy: -4)
    }

    /// Um monitor está num espaço de tela cheia quando o fundo da mesa saiu dele. Em tela cheia o macOS tira dali
    /// a janela do papel de parede e a da mesa do Finder (visto com `CGWindowListCopyWindowInfo`), e é o único
    /// sinal público: a janela do app em tela cheia tem o mesmo tamanho de uma janela maximizada com o Dock oculto.
    /// `mesa`: as janelas do fundo existem, à vista ou não. Sem elas (o Finder sem mesa e o papel de parede fora do ar),
    /// não dá para saber, e a ilha fica. Com elas e nenhuma à vista (o MacBook sozinho em tela cheia), é tela cheia.
    /// `tela` e `fundos` em coordenadas do Quartz (origem no canto de cima do monitor principal).
    static func emTelaCheia(tela: CGRect, fundos: [CGRect], mesa: Bool) -> Bool {
        mesa && !fundos.contains { $0.insetBy(dx: -1, dy: -1).contains(tela) }
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
    let hoje: Bool
    /// O próximo jogo ou corrida que a pessoa segue, nos próximos 7 dias.
    let interesse: Bool
    let sessoes: Int
    let tocando: Bool
    let linhas: Int
    /// Emblemas do Dock, microfone, câmera e bateria numa linha.
    let apps: Bool
    let bandeja: Bool

    init(tocando: Bool, atividades: Int, arquivos: Int, arrastando: Bool, sessoes: Int = 0, hoje: Bool = false,
         apps: Bool = false, interesse: Bool = false) {
        self.hoje = hoje
        self.interesse = interesse
        self.sessoes = min(sessoes, Geometria.maximoSessoes)
        self.tocando = tocando
        linhas = min(atividades, Geometria.maximoLinhas)
        self.apps = apps
        // Sem nada para mostrar, a ilha aberta oferece a bandeja vazia: é o que dá para fazer com ela.
        bandeja = arquivos > 0 || arrastando || (atividades == 0 && !tocando && sessoes == 0 && !hoje && !apps && !interesse)
    }
}
