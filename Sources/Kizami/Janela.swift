import AppKit
import Observation
import SwiftUI

/// Estado de uma ilha que a view observa.
@MainActor @Observable
final class EstadoIlha {
    var geometria: Geometria
    var aberta = false
    /// Um arquivo arrastado está em cima da ilha: a área de soltar acende.
    var alvo = false
    var aba: Aba = .inicio
    /// Um atalho foi clicado: a ilha fecha e só volta a abrir depois que o cursor sai e volta.
    var recolher = false
    /// A linha da lista sob o cursor: só ela mostra o ✕ (a view não tem `@State` sem as macros).
    var linhaSobCursor: String?
    /// O cartão do Início sob o cursor: só ele clareia.
    var cartaoSobCursor: String?
    /// O item do Início que cresceu no lugar (clique no chip da agenda ou na linha do que está tocando). Fechar a
    /// ilha recolhe (`Janela.recolher`).
    var expandido: Expansao?
    /// O dia escolhido na agenda expandida; `nil` é hoje.
    var diaEscolhido: Date?
    /// A agenda expandida mostra o mês em vez da semana.
    var mesInteiro = false
    /// Onde a faixa está, lido pela `Janela` só com a música expandida.
    var progresso: Progresso?
    /// O dedo na barra da música: a fração em que ela está, até soltar e pular para lá.
    var arrastandoEm: Double?

    enum Expansao: Equatable { case agenda, musica }

    init(geometria: Geometria) {
        self.geometria = geometria
    }
}

/// A ilha de um monitor: painel sem borda no topo da tela, do tamanho da maior forma. A forma preta anima
/// dentro dele (SwiftUI): animar o frame da janela trava. Fechada, deixa os cliques passarem para a barra de menus.
/// O `Kizami` cria uma por tela e recria todas quando monitores entram, saem ou a tampa fecha.
@MainActor
final class Janela {
    private let painel: NSPanel
    private let estado: EstadoIlha
    private let fontes: Fontes
    private var mural: Mural { fontes.mural }
    private var bandeja: Bandeja { fontes.bandeja }
    private var vigia: Task<Void, Never>?
    /// Quando o cursor entrou na área que abre a ilha fechada.
    private var entrada: Date?
    /// O cursor precisa parar no notch este tempo: passar por ele a caminho dos menus da direita não abre a ilha.
    private static let permanencia: TimeInterval = 0.15
    /// O monitor em coordenadas do Quartz, as da lista de janelas do macOS.
    private let telaQuartz: CGRect
    /// O monitor está num espaço de tela cheia: a ilha sai dele (pedido da pessoa: em vídeo ou jogo, ela atrapalha).
    private(set) var oculta = false
    /// O painel está na tela. Em tela cheia, só volta para um aviso urgente, se a pessoa ligou isso nos Ajustes.
    private var visivel = true
    /// Esta ilha está mostrando o espelho: só a `Janela` liga e desliga a câmera, nunca o ciclo de vida da view
    /// (um `onAppear` atrasado ligaria a câmera com a ilha já fechada).
    private var comCamera = false
    /// A leitura da posição da música expandida (`acertarProgresso`).
    private var leitor: Task<Void, Never>?
    static let chaveUrgenteEmTelaCheia = "ilha.urgenteEmTelaCheia"

    init(fontes: Fontes, tela: NSScreen) {
        self.fontes = fontes
        let numero = tela.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        telaQuartz = numero.map(CGDisplayBounds) ?? .null
        let geometria = Geometria(tela: tela.frame, esquerda: tela.auxiliaryTopLeftArea?.width,
                                  direita: tela.auxiliaryTopRightArea?.width, topoSeguro: tela.safeAreaInsets.top,
                                  barraDeMenus: NSStatusBar.system.thickness)
        estado = EstadoIlha(geometria: geometria)
        painel = NSPanel(contentRect: geometria.janela, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        painel.level = .mainMenu + 3  // acima da barra de menus; o .statusBar (25) fica logo acima dela e não basta (boring.notch usa este)
        // Sem .fullScreenAuxiliary não basta para sumir em tela cheia: neste nível, o macOS mostra o painel
        // também no espaço do app em tela cheia (visto com o YouTube no Chrome). Quem esconde é `ajustar(fundos:)`.
        painel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        painel.backgroundColor = .clear
        painel.isOpaque = false
        painel.hasShadow = false  // a sombra vem do SwiftUI e acompanha a forma
        painel.hidesOnDeactivate = false
        painel.isMovable = false
        painel.ignoresMouseEvents = true
        painel.appearance = NSAppearance(named: .darkAqua)  // texto claro sobre o preto, com o Mac em modo claro ou escuro
        let host = NSHostingView(rootView: IlhaView(estado: estado, fontes: fontes))
        host.sizingOptions = []  // o tamanho é o da Geometria, não o do conteúdo
        painel.contentView = host
        painel.setFrame(geometria.janela, display: true)
        painel.orderFrontRegardless()  // nunca makeKey nem activate: o foco fica no app em que a pessoa está
        vigiar()
    }

    /// Esconde a ilha no monitor que está em tela cheia e devolve quando sai dela. `fundos`: as janelas do fundo
    /// da mesa que estão à vista (`Geometria.emTelaCheia`).
    func ajustar(fundos: [CGRect], mesa: Bool) {
        let cheia = Geometria.emTelaCheia(tela: telaQuartz, fundos: fundos, mesa: mesa)
        guard cheia != oculta else { return }
        oculta = cheia
        if cheia { recolher() }
        mostrarOuEsconder()
    }

    /// Em tela cheia, a ilha some, a não ser que haja um aviso urgente (reunião começando, o Claude pedindo
    /// permissão) e a pessoa tenha ligado isso: o mesmo painel já é desenhado por cima da tela cheia
    /// (`.canJoinAllSpaces` neste nível), então basta não escondê-lo. Só o aviso aparece; o hover segue desligado.
    private func mostrarOuEsconder() {
        let urgente = UserDefaults.standard.bool(forKey: Self.chaveUrgenteEmTelaCheia)
            // Só as fontes do próprio Kizami (as que têm ação de clique): um "urgente" mandado pelo `Kizami enviar`
            // não fura a tela cheia.
            // ponytail: o "Claude precisa de você" vem do hook, que qualquer processo local também pode imitar; o
            // texto é fixo e a pasta é limpa, então o pior é um aviso falso de 3,5 s. Exigir sessão antiga se abusarem.
            && mural.avisos.contains { $0.prioridade == "urgente" && mural.podeAbrir($0.id) }
        let deveMostrar = !oculta || urgente
        guard deveMostrar != visivel else { return }
        visivel = deveMostrar
        if deveMostrar { painel.orderFrontRegardless() } else { painel.orderOut(nil) }
    }

    func fechar() {
        vigia?.cancel()
        recolher()
        painel.orderOut(nil)
    }

    /// Fecha a ilha por qualquer caminho (cursor saiu, tela cheia, monitor saiu): volta ao Início e desliga a câmera.
    private func recolher() {
        estado.aberta = false
        painel.ignoresMouseEvents = true
        // Só a ilha que tinha a agenda expandida para de ler o mês: a Agenda é a mesma em todos os monitores.
        if estado.expandido == .agenda { fontes.agenda.mostrar(nil) }
        estado.expandido = nil
        estado.cartaoSobCursor = nil  // o fim do hover pode não chegar quando a view some ao fechar
        estado.diaEscolhido = nil
        estado.mesInteiro = false
        acertarCamera()
        acertarProgresso()
    }

    /// Lê onde a faixa está uma vez por segundo, só com a música expandida e a ilha aberta e à vista. Liga e desliga
    /// aqui, como a câmera, e não no ciclo de vida da view: um `onDisappear` atrasado deixaria o `osascript` rodando.
    private func acertarProgresso() {
        let quer = estado.aberta && !oculta && expansaoAtual(estado, fontes) == .musica
            && fontes.tocando.app.map(Controle.sabeControlar) == true
        guard quer != (leitor != nil) else { return }
        leitor?.cancel()
        leitor = nil
        guard quer else {
            estado.progresso = nil
            estado.arrastandoEm = nil
            return
        }
        leitor = Task { [weak self] in
            while !Task.isCancelled {
                if let app = self?.fontes.tocando.app, let script = Controle.scriptDaPosicao(app: app) {
                    let resposta = await AppleScript.rodar(script)
                    guard let self, !Task.isCancelled else { return }
                    let lido = resposta.flatMap { Progresso.ler($0, app: app, agora: .now) }
                    // A leitura que só confirma o relógio local não muda nada na tela.
                    let mudou = switch (self.estado.progresso, lido) {
                    case let (atual?, lido?): atual.difere(de: lido)
                    default: lido != self.estado.progresso
                    }
                    if mudou { self.estado.progresso = lido }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func acertarCamera() {
        let quer = estado.aberta && estado.aba == .espelho && !oculta
        guard quer != comCamera else { return }
        comCamera = quer
        if quer { fontes.espelho.ligar() } else { fontes.espelho.desligar() }
    }

    // ponytail: consulta a posição do cursor em cada monitor: a cada 50 ms com o cursor perto do topo ou a ilha aberta,
    // a cada 100 ms longe dele (com 250 ms, o cursor jogado direto no notch esperava até 250 ms para ser visto, mais os
    // 150 ms de permanência, e a ilha parecia lenta para responder). É o jeito que não depende de evento chegar a
    // uma janela que nunca vira key; trocar por um monitor global de .mouseMoved se o consumo de energia aparecer.
    private func vigiar() {
        vigia = Task { [weak self] in
            while !Task.isCancelled {
                guard let intervalo = self?.conferir() else { return }
                try? await Task.sleep(for: intervalo)
            }
        }
    }

    /// A asa mostra a música pausada agora (nada de aviso, volume ou outra coisa na frente).
    private var musicaPausadaNaAsa: Bool {
        fontes.mural.avisos.isEmpty && !fontes.volume.naAsa && fontes.tocando.pausado && asaAtual(fontes) == .tocando
    }

    /// Abre ou fecha conforme o cursor e devolve quanto esperar até a próxima consulta.
    /// Também chamada a cada movimento de um arraste de arquivo (`Arrasto`).
    @discardableResult func conferir() -> Duration {
        let botao = NSEvent.pressedMouseButtons & 1 != 0
        // O monitor global não vê a soltura que cai na própria ilha (nem um arraste cancelado com esc):
        // sem o botão apertado, não há arraste, e a ilha não pode ficar presa aberta sobre a barra de menus.
        if bandeja.arrastando && !botao { bandeja.arrastando = false }
        mostrarOuEsconder()  // o aviso urgente chega e sai a qualquer momento; a consulta já roda a cada 50–250 ms
        let g = estado.geometria
        // Fechada, a zona tem o tamanho que a ilha desenha agora (aviso, asas do timer, do placar, dos ícones), e as
        // asas no mínimo: arrastando, a ilha em repouso também aceita o arquivo.
        let desenhada = tamanhoFechado(g, fontes)
        let fechada = CGSize(width: max(desenhada.width, g.compacta.width), height: desenhada.height)
        let zona = if estado.aberta {
            g.zona(tamanhoAberto(g, estado, fontes))
        } else if bandeja.arrastando {
            g.zona(fechada)  // arrastando, as asas também valem: ninguém clica num menu no meio de um arraste
        } else if !mural.avisos.isEmpty {
            g.zona(fechada)  // o aviso já está à vista: passar o cursor nele abre a lista
        } else {
            g.gatilho
        }
        let cursor = NSEvent.mouseLocation
        // Aberta e com o botão apertado, fica aberta: um arquivo arrastado para fora da bandeja ainda está em viagem,
        // e fechar trocaria a view de origem no meio do arraste.
        // Escondida em tela cheia: sem isto, a ilha "abriria" invisível e encerraria o aviso que ninguém viu.
        if estado.recolher && !zona.contains(cursor) { estado.recolher = false }
        let dentro = !oculta && !estado.recolher && zona.contains(cursor)
        entrada = dentro ? (entrada ?? .now) : nil
        // A ilha está sempre lá e abre mesmo vazia, para mostrar a bandeja. Fechada, só abre se o cursor parar;
        // com um arquivo sendo arrastado, abre na hora.
        let aberta = if estado.aberta {
            dentro || botao
        } else {
            dentro && (bandeja.arrastando || Date.now.timeIntervalSince(entrada ?? .now) >= Self.permanencia)
        }
        if aberta != estado.aberta {
            if aberta {
                estado.aberta = true
                painel.ignoresMouseEvents = false  // aberta, o clique fica na ilha em vez de cair na janela de baixo
                // Com aviso, atividade ou um arquivo sendo arrastado, abre no Início, onde estão a lista e a bandeja
                // (o aviso se encerra logo abaixo); sem, na primeira aba da pessoa. Decidido ao abrir: a escolha pode
                // ter mudado nos Ajustes.
                let noInicio = !mural.atividades.isEmpty || !mural.avisos.isEmpty || bandeja.arrastando
                estado.aba = noInicio ? .inicio : fontes.personalizacao.abaInicial
                mural.encerrarAviso()
                bandeja.podar()
            } else {
                recolher()
            }
        }
        // Fechada com a música pausada, o "pausado" da asa vira botão de tocar: só ali o clique fica na ilha. Fora dele
        // (e em qualquer outro estado fechado) a ilha ignora o mouse, e a barra de menus continua recebendo tudo.
        if !estado.aberta {
            let noBotao = !oculta && musicaPausadaNaAsa && g.botaoDaAsa(desenhada).contains(cursor)
            if painel.ignoresMouseEvents == noBotao { painel.ignoresMouseEvents = !noBotao }
        }
        acertarCamera()  // entrou ou saiu da aba Espelho com a ilha aberta
        acertarProgresso()  // expandiu ou recolheu a música
        // Trocou de aba com a agenda expandida: ela recolhe e o mês para de ser lido, que fora da tela ninguém vê.
        if estado.expandido == .agenda && expansaoAtual(estado, fontes) != .agenda {
            fontes.agenda.mostrar(nil)
            estado.expandido = nil
        }
        let pertoDoTopo = g.tela.contains(cursor) && cursor.y > g.tela.maxY - 120
        return .milliseconds(estado.aberta || pertoDoTopo ? 50 : 100)
    }
}
