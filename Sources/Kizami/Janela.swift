import AppKit
import Observation
import SwiftUI

/// Estado da ilha que a view observa.
@MainActor @Observable
final class EstadoIlha {
    var geometria = Geometria(tela: .zero, esquerda: nil, direita: nil, topoSeguro: 0, barraDeMenus: 24)
    var aberta = false
}

/// Painel sem borda no topo da tela, do tamanho da ilha aberta. A forma preta anima dentro dele (SwiftUI):
/// animar o frame da janela trava. Fechada, a janela deixa os cliques passarem para a barra de menus.
@MainActor
final class Janela {
    private let painel: NSPanel
    private let estado = EstadoIlha()
    private let mural: Mural

    init(mural: Mural) {
        self.mural = mural
        painel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        painel.level = .mainMenu + 3  // acima da barra de menus; o .statusBar (25) fica logo acima dela e não basta (boring.notch usa este)
        painel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        painel.backgroundColor = .clear
        painel.isOpaque = false
        painel.hasShadow = false
        painel.hidesOnDeactivate = false
        painel.isMovable = false
        painel.ignoresMouseEvents = true
        painel.appearance = NSAppearance(named: .darkAqua)  // texto claro sobre o preto, com o Mac em modo claro ou escuro
        let host = NSHostingView(rootView: IlhaView(estado: estado, mural: mural))
        host.sizingOptions = []  // o tamanho é o da Geometria, não o do conteúdo
        painel.contentView = host

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.posicionar() }
        }
        posicionar()
        painel.orderFrontRegardless()  // nunca makeKey nem activate: o foco fica no app em que a pessoa está
        vigiarCursor()
    }

    /// Na tela com notch; sem nenhuma, na principal. Roda de novo quando monitores entram, saem ou a tampa fecha.
    private func posicionar() {
        guard let tela = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let geometria = Geometria(tela: tela.frame, esquerda: tela.auxiliaryTopLeftArea?.width,
                                  direita: tela.auxiliaryTopRightArea?.width, topoSeguro: tela.safeAreaInsets.top,
                                  barraDeMenus: NSStatusBar.system.thickness)
        estado.geometria = geometria
        painel.setFrame(geometria.retangulo(geometria.aberta), display: true)
        registro.info("ilha em \(geometria.temNotch ? "tela com notch" : "tela sem notch", privacy: .public)")
    }

    // ponytail: consulta a posição do cursor a cada 70 ms enquanto há atividade (2 vezes por segundo sem nenhuma).
    // É o jeito que não depende de evento chegar a uma janela que nunca vira key; trocar por um monitor global
    // de .mouseMoved se o consumo de energia aparecer no Monitor de Atividade.
    private func vigiarCursor() {
        Task { [weak self] in
            while let self {
                let ativa = !self.mural.atividades.isEmpty
                self.conferirCursor(ativa: ativa)
                try? await Task.sleep(for: .milliseconds(ativa ? 70 : 500))
            }
        }
    }

    private func conferirCursor(ativa: Bool) {
        let cursor = NSEvent.mouseLocation
        let g = estado.geometria
        let aberta = ativa && (estado.aberta ? g.zona(g.aberta) : g.gatilho).contains(cursor)
        guard aberta != estado.aberta else { return }
        estado.aberta = aberta
        painel.ignoresMouseEvents = !aberta  // aberta, o clique fica na ilha em vez de cair na janela de baixo
    }
}
