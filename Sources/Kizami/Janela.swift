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

    enum Aba { case inicio, atalhos }

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
        if cheia {
            painel.orderOut(nil)
            estado.aberta = false
            painel.ignoresMouseEvents = true
        } else {
            painel.orderFrontRegardless()
        }
    }

    func fechar() {
        vigia?.cancel()
        painel.orderOut(nil)
    }

    // ponytail: consulta a posição do cursor em cada monitor: a cada 50 ms com o cursor perto do topo ou a ilha aberta,
    // a cada 250 ms longe dele. É o jeito que não depende de evento chegar a
    // uma janela que nunca vira key; trocar por um monitor global de .mouseMoved se o consumo de energia aparecer.
    private func vigiar() {
        vigia = Task { [weak self] in
            while !Task.isCancelled {
                guard let intervalo = self?.conferir() else { return }
                try? await Task.sleep(for: intervalo)
            }
        }
    }

    /// Abre ou fecha conforme o cursor e devolve quanto esperar até a próxima consulta.
    /// Também chamada a cada movimento de um arraste de arquivo (`Arrasto`).
    @discardableResult func conferir() -> Duration {
        let botao = NSEvent.pressedMouseButtons & 1 != 0
        // O monitor global não vê a soltura que cai na própria ilha (nem um arraste cancelado com esc):
        // sem o botão apertado, não há arraste, e a ilha não pode ficar presa aberta sobre a barra de menus.
        if bandeja.arrastando && !botao { bandeja.arrastando = false }
        let g = estado.geometria
        // Fechada, a zona tem o tamanho que a ilha desenha agora (aviso ou asas com até três ícones).
        let fechada = mural.avisos.isEmpty ? g.compacta(icones: mural.destaques.count) : g.aviso(linhas: mural.avisos.count)
        let zona = if estado.aberta {
            g.zona(estado.aba == .atalhos ? g.abertaAtalhos : g.aberta(secoesAtuais(fontes)))
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
            estado.aberta = aberta
            painel.ignoresMouseEvents = !aberta  // aberta, o clique fica na ilha em vez de cair na janela de baixo
            if aberta {
                mural.encerrarAviso()
                bandeja.podar()
            } else {
                estado.aba = .inicio  // abre sempre no início, que é onde está o que chegou
            }
        }
        let pertoDoTopo = g.tela.contains(cursor) && cursor.y > g.tela.maxY - 120
        return .milliseconds(estado.aberta || pertoDoTopo ? 50 : 250)
    }
}
