import AppKit
import SwiftUI

/// As molas da ilha num lugar só: cada view com a sua dava movimentos parecidos mas diferentes, e a ilha parecia
/// feita de peças. Abrir tem um pouco de quique (a ilha "cai" do notch); fechar e trocar conteúdo, quase nenhum.
enum Movimento {
    static let abrir = Animation.spring(response: 0.44, dampingFraction: 0.74)
    static let fechar = Animation.spring(response: 0.34, dampingFraction: 0.92)
    static let conteudo = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let expandir = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let rapido = Animation.smooth(duration: 0.2)
    /// Entre as seções que entram uma depois da outra: o bastante para o olho seguir, pouco para parecer lento.
    static let escalonamento: Double = 0.035

    /// Com "Reduzir movimento" nos Ajustes do Sistema, troca sem mola nem deslocamento.
    static func ou(_ animacao: Animation) -> Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration: 0.15) : animacao
    }
}

/// O vidro (Liquid Glass) dos chips, cartões e botões de dentro da ilha. A ilha em si continua preta: ela se funde
/// ao notch, e um vidro ali deixaria a emenda com o recorte da tela à vista.
extension View {
    func vidro(raio: CGFloat = Geometria.raioDoCartao) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: raio, style: .continuous))
    }

    /// Com um id, o vidro muda de forma para o do mesmo id quando um item expande ou recolhe (`glassEffectID`).
    /// Os dois precisam estar dentro do mesmo `GlassEffectContainer`.
    func vidro(raio: CGFloat = Geometria.raioDoCartao, id: String, em espaco: Namespace.ID) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: raio, style: .continuous))
            .glassEffectID(id, in: espaco)
    }
}

extension View {
    /// As seções do Início entram uma depois da outra, descendo 6 pt: a ilha abre como uma lista que se desdobra.
    /// Com "Reduzir movimento", só o esmaecer, sem deslocamento nem espera.
    func entrada(_ ordem: Int) -> some View {
        let reduzir = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let chegada: AnyTransition = reduzir ? .opacity
            : .opacity.combined(with: .offset(y: -6))
                .animation(Movimento.conteudo.delay(Double(ordem) * Movimento.escalonamento))
        return transition(.asymmetric(insertion: chegada, removal: .opacity))
    }
}
