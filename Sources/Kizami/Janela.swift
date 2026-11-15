import AppKit
import Observation
import SwiftUI

/// Estado de uma ilha que a view observa.
@MainActor @Observable
final class EstadoIlha {
    var geometria: Geometria
    var aberta = false

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
    private let mural: Mural
    private var vigia: Task<Void, Never>?

    init(mural: Mural, tela: NSScreen) {
        self.mural = mural
        let geometria = Geometria(tela: tela.frame, esquerda: tela.auxiliaryTopLeftArea?.width,
                                  direita: tela.auxiliaryTopRightArea?.width, topoSeguro: tela.safeAreaInsets.top,
                                  barraDeMenus: NSStatusBar.system.thickness)
        estado = EstadoIlha(geometria: geometria)
        painel = NSPanel(contentRect: geometria.janela, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        painel.level = .mainMenu + 3  // acima da barra de menus; o .statusBar (25) fica logo acima dela e não basta (boring.notch usa este)
        painel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        painel.backgroundColor = .clear
        painel.isOpaque = false
        painel.hasShadow = false  // a sombra vem do SwiftUI e acompanha a forma
        painel.hidesOnDeactivate = false
        painel.isMovable = false
        painel.ignoresMouseEvents = true
        painel.appearance = NSAppearance(named: .darkAqua)  // texto claro sobre o preto, com o Mac em modo claro ou escuro
        let host = NSHostingView(rootView: IlhaView(estado: estado, mural: mural))
        host.sizingOptions = []  // o tamanho é o da Geometria, não o do conteúdo
        painel.contentView = host
        painel.setFrame(geometria.janela, display: true)
        painel.orderFrontRegardless()  // nunca makeKey nem activate: o foco fica no app em que a pessoa está
        vigiar()
    }

    func fechar() {
        vigia?.cancel()
        painel.orderOut(nil)
    }

    // ponytail: consulta a posição do cursor a cada 50 ms enquanto há atividade (2 vezes por segundo sem nenhuma),
    // em cada monitor. É o jeito que não depende de evento chegar a uma janela que nunca vira key; trocar por um
    // monitor global de .mouseMoved se o consumo de energia aparecer no Monitor de Atividade.
    private func vigiar() {
        vigia = Task { [weak self] in
            while !Task.isCancelled {
                guard let intervalo = self?.conferirCursor() else { return }
                try? await Task.sleep(for: intervalo)
            }
        }
    }

    /// Abre ou fecha conforme o cursor e devolve quanto esperar até a próxima consulta.
    private func conferirCursor() -> Duration {
        let ativa = !mural.atividades.isEmpty
        let g = estado.geometria
        let zona = if estado.aberta {
            g.zona(g.aberta(linhas: mural.atividades.count))
        } else if mural.novidade != nil {
            g.zona(g.aviso)  // o aviso já está à vista: passar o cursor nele abre a lista
        } else {
            g.gatilho
        }
        let aberta = ativa && zona.contains(NSEvent.mouseLocation)
        if aberta != estado.aberta {
            estado.aberta = aberta
            painel.ignoresMouseEvents = !aberta  // aberta, o clique fica na ilha em vez de cair na janela de baixo
            if aberta { mural.encerrarAviso() }
        }
        return .milliseconds(ativa ? 50 : 500)
    }
}
