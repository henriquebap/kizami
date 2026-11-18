import CoreGraphics

/// Onde a ilha fica numa tela e de que tamanho é em cada estado. Regra pura, sem AppKit,
/// para testar com as medidas de telas reais. Coordenadas do AppKit: o topo da tela é `maxY`.
struct Geometria: Equatable {
    /// Espaço de cada lado do notch para o ícone e o contador; o centro é a câmera.
    static let asa: CGFloat = 34
    /// A curva côncava no topo que funde a ilha com a borda da tela, como no notch de verdade.
    static let orelha: CGFloat = 8
    static let larguraAviso: CGFloat = 300
    /// A grade de duas colunas pede mais que os 340 pt da lista de antes; com 20 pt de margem dos lados, cada widget
    /// fica com 166 pt, o bastante para o rótulo e o número sem reticências. Com 420 tudo parecia grande demais.
    static let larguraAberta: CGFloat = 380
    static let alturaLinha: CGFloat = 30
    static let espacoLinha: CGFloat = 4
    static let maximoLinhas = 3
    /// A fileira de arquivos da bandeja, abaixo da lista.
    static let alturaBandeja: CGFloat = 64
    static let espacoSecao: CGFloat = 10
    /// O canto das linhas (avisos, eventos) dentro da ilha aberta.
    static let raioDoCartao: CGFloat = 12
    /// O canto dos widgets e do cartão de destaque: concêntrico com o canto de 30 pt da ilha aberta, menos a folga.
    static let raioDoWidget: CGFloat = 20
    /// O topo da ilha aberta: as abas (Início, Atalhos) e a engrenagem dos Ajustes.
    static let alturaCabecalho: CGFloat = 26
    /// A fileira de atalhos: ícone, nome e teclas.
    static let alturaAtalhos: CGFloat = 62
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

    /// Com o cursor em cima: o Início em grade, uma fileira embaixo da outra.
    func aberta(_ painel: Painel) -> CGSize {
        abertaComAba(painel.altura)
    }

    /// A aba de atalhos: o cabeçalho e a fileira.
    var abertaAtalhos: CGSize { abertaComAba(Self.alturaAtalhos) }

    /// A aba do Kanji: a fileira das ações e, com skills, a fileira delas (44 pt) logo abaixo.
    static func alturaKanji(skills: Int) -> CGFloat { alturaComFileira(skills) }

    /// A fileira de 62 pt e, se houver itens, uma segunda de 44 pt embaixo (skills do Kanji, Atalhos da Apple).
    static func alturaComFileira(_ itens: Int) -> CGFloat { alturaAtalhos + (itens > 0 ? 6 + 44 : 0) }

    /// A aba Hoje: um evento por linha, até `maximoDoDia` (o último vira "mais N"), ou a linha do "nada mais".
    static let maximoDoDia = 5
    static func alturaDoDia(eventos: Int) -> CGFloat { alturaDaLista(itens: eventos) }

    /// Uma aba em lista (Hoje, Copiados): até `maximoDoDia` linhas, ou a linha do vazio.
    static func alturaDaLista(itens: Int) -> CGFloat { alturaLinhas(max(1, min(itens, maximoDoDia))) }

    /// `n` linhas da lista com o espaço entre elas.
    static func alturaLinhas(_ n: Int) -> CGFloat { n > 0 ? CGFloat(n) * alturaLinha + CGFloat(n - 1) * espacoLinha : 0 }

    /// A música expandida: a capa grande com o título e os botões ao lado e, se o player diz onde está (Music,
    /// Spotify), a barra do tempo embaixo. Num navegador não há barra.
    static let capaGrande: CGFloat = 84
    static func alturaMusica(barra: Bool) -> CGFloat { 12 + capaGrande + (barra ? 10 + 22 : 0) + 12 }

    /// A agenda expandida: a linha do mês com Semana/Mês, a faixa da semana (ou a grade de `semanas` fileiras)
    /// e os eventos do dia escolhido, como na aba Hoje (até `maximoDoDia` linhas, sem rolagem).
    static let alturaDaFaixa: CGFloat = 40
    static let alturaDaFileiraDoMes: CGFloat = 24
    static func alturaAgenda(semanas: Int, eventos: Int) -> CGFloat {
        let grade = semanas <= 1 ? alturaDaFaixa : 14 + CGFloat(semanas) * alturaDaFileiraDoMes
        return 10 + 24 + 8 + grade + 8 + alturaDaLista(itens: eventos) + 10
    }

    /// Uma aba que não é o Início: o cabeçalho e o conteúdo dela (atalhos, Kanji).
    func abertaComAba(_ conteudo: CGFloat) -> CGSize {
        CGSize(width: max(Self.larguraAberta, compacta.width),
               height: faixaDoTopo + 8 + Self.alturaCabecalho + Self.espacoSecao + conteudo + 14)
    }

    /// O quadradinho do lado direito da asa fechada (o "pausado" da música), com 4 pt de folga para o cursor. É a
    /// única parte da ilha fechada que recebe clique: fora dele a barra de menus continua recebendo tudo.
    func botaoDaAsa(_ tamanho: CGSize) -> CGRect {
        let lado = min(20, notch.height - 12)
        let r = retangulo(tamanho)
        let x = r.maxX - Self.orelha - ((notch.height - lado) / 2 + 2) - lado
        return CGRect(x: x, y: r.minY + (r.height - lado) / 2, width: lado, height: lado).insetBy(dx: -4, dy: -4)
    }

    /// A janela tem o tamanho do maior estado mais a margem da sombra; a forma anima dentro dela.
    var janela: CGRect {
        let maior = aberta(Painel.maior)
        // A fechada com três ícones passa da aberta num notch mais largo que ~204 pt.
        let largura = max(maior.width, compacta(icones: 3).width, aviso(linhas: 3).width)
        // O mês de seis semanas com a lista cheia: hoje cabe na maior do Início, mas não depende disso.
        let altura = max(maior.height, abertaComAba(Self.alturaAgenda(semanas: 6, eventos: Self.maximoDoDia)).height)
        return retangulo(CGSize(width: largura + 2 * Self.sombra, height: altura + Self.sombra))
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

/// O Início em grade (v0.16): o destaque e as faixas largas ocupam as duas colunas; os widgets, uma cada, aos pares.
/// A janela (área do hover) e a view medem com a mesma regra, como antes.
struct Painel: Equatable, Sendable {
    /// O que ocupa as duas colunas.
    enum Largo: Hashable, Sendable {
        /// Uma sessão do Claude precisa de você; `outras`: há mais sessões, que viram pílulas embaixo.
        case claude(outras: Bool)
        /// Uma reunião prestes a começar (`Agenda.emBreve`: de 10 min antes a 5 min depois); `link`: tem o botão de
        /// entrar, que pede uma linha a mais.
        case reuniao(link: Bool)
        case musica
        /// O dia calmo: a data, a temperatura, a régua das 8h às 20h e até três eventos que faltam hoje.
        case dia(eventos: Int)
        /// Os avisos que chegaram, até três linhas.
        case atividades(Int)
        /// Os arquivos guardados, ou a área de soltar durante um arraste.
        case bandeja
    }

    /// Um quadrado da grade.
    enum Widget: String, CaseIterable, Hashable, Sendable { case tempo, agenda, sessoes, musica, timer, lembretes, interesse, mac }

    enum Fileira: Hashable, Sendable {
        case larga(Largo)
        case dupla(Widget, Widget)
        /// Um widget sem par ocupa a fileira toda: um quadrado sozinho deixaria um buraco ao lado.
        case sozinha(Widget)
    }

    /// O que existe agora, já com o que a pessoa escondeu nos Ajustes fora.
    struct Entrada: Equatable, Sendable {
        var precisaDeVoce = false
        var sessoes = 0
        var reuniao = false
        var reuniaoComLink = false
        var tocando = false
        /// O timer está correndo ou pausado (vem antes na grade). Parado, ele só entra para fechar um par.
        var timer = false
        /// A faixa "Hoje" (tempo e agenda) está à vista: sem ela, também não há o cartão do dia.
        var hoje = true
        var tempo = false
        var agenda = false
        /// Os eventos que ainda faltam hoje, para a lista do cartão do dia.
        var eventosHoje = 0
        var lembretes = 0
        var interesse = false
        var mac = false
        var atividades = 0
        var bandeja = false
    }

    /// Seis widgets no máximo: três fileiras. Mais que isso a ilha passaria da metade da tela de um MacBook.
    static let maximoWidgets = 6

    let fileiras: [Fileira]

    init(_ e: Entrada) {
        // O destaque: quem pede ação primeiro (o Claude parado esperando), depois o que tem hora (a reunião), depois
        // o que está acontecendo (a música). Sem nada disso, o dia.
        let destaque: Largo? = e.precisaDeVoce ? .claude(outras: e.sessoes > 1)
            : e.reuniao ? .reuniao(link: e.reuniaoComLink)
            : e.tocando ? .musica
            : e.hoje ? .dia(eventos: min(e.eventosHoje, 3))
            : nil
        let dia = destaque.map { if case .dia = $0 { true } else { false } } ?? false
        var widgets: [Widget] = []
        if e.hoje && e.tempo && !dia { widgets.append(.tempo) }
        if e.hoje && e.agenda && !dia && !e.reuniao { widgets.append(.agenda) }
        if e.sessoes > 0 && !e.precisaDeVoce { widgets.append(.sessoes) }
        if e.tocando && destaque != .musica { widgets.append(.musica) }
        if e.timer { widgets.append(.timer) }
        if e.lembretes > 0 { widgets.append(.lembretes) }
        if e.interesse { widgets.append(.interesse) }
        if e.mac { widgets.append(.mac) }
        widgets = Array(widgets.prefix(Self.maximoWidgets))
        // Ímpar, o último ficaria sozinho na fileira toda: o timer parado entra para fechar o par (é sempre útil, um
        // clique começa um foco). Com o timer já na grade, o último fica largo mesmo.
        if widgets.count % 2 == 1 && !widgets.contains(.timer) { widgets.append(.timer) }

        var f: [Fileira] = destaque.map { [.larga($0)] } ?? []
        if e.atividades > 0 { f.append(.larga(.atividades(min(e.atividades, Geometria.maximoLinhas)))) }
        f += stride(from: 0, to: widgets.count, by: 2).map { i in
            i + 1 < widgets.count ? .dupla(widgets[i], widgets[i + 1]) : .sozinha(widgets[i])
        }
        if e.bandeja { f.append(.larga(.bandeja)) }
        fileiras = f
    }

    static let espaco: CGFloat = 8

    /// A altura da grade, sem o cabeçalho.
    var altura: CGFloat {
        let alturas = fileiras.map { fileira -> CGFloat in
            switch fileira {
            case .dupla, .sozinha: Self.alturaWidget
            case .larga(let largo): Self.altura(largo)
            }
        }
        return alturas.reduce(0, +) + CGFloat(max(alturas.count - 1, 0)) * Self.espaco
    }

    /// Rótulo, número de 24 pt e uma linha de detalhe com o botão Entrar, e 12 pt de folga em volta.
    static let alturaWidget: CGFloat = 92
    /// A folga dentro dos cartões largos e o círculo do ícone deles (Claude, reunião).
    static let folga: CGFloat = 12
    static let icone: CGFloat = 36
    /// O cartão de destaque: a folga, a linha principal e a de baixo (pílulas, botões).
    static func altura(_ largo: Largo) -> CGFloat {
        switch largo {
        case .claude(let outras): outras ? folga + icone + 10 + 24 + folga : folga + icone + folga
        case .reuniao(let link): link ? folga + icone + 10 + 28 + folga : folga + icone + folga
        case .musica: folga + capaDoCartao + folga
        case .dia(let eventos): alturaDia(eventos: eventos)
        case .atividades(let n): Geometria.alturaLinhas(n)
        case .bandeja: Geometria.alturaBandeja
        }
    }

    static let capaDoCartao: CGFloat = 48
    static let cabecaDoDia: CGFloat = 44
    static let reguaDoDia: CGFloat = 34
    static let linhaDoDia: CGFloat = 22
    /// Cabeça (data e temperatura), a régua e uma linha por evento que falta.
    static func alturaDia(eventos: Int) -> CGFloat {
        folga + cabecaDoDia + 8 + reguaDoDia + (eventos > 0 ? 6 + CGFloat(min(eventos, 3)) * linhaDoDia : 0) + folga
    }

    /// O Início mais alto possível, para a janela caber qualquer estado.
    static var maior: Painel {
        Painel(Entrada(sessoes: 3, timer: true, eventosHoje: 3, lembretes: 3, interesse: true, mac: true,
                       atividades: Geometria.maximoLinhas, bandeja: true))
    }
}
