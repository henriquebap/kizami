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

/// A escala de tipo da ilha (v0.16). Antes quase tudo ia de 10 a 13 pt e nada saltava aos olhos; agora o número que
/// importa (a temperatura, a hora, os minutos que faltam) é grande e arredondado, o título é médio e o resto recua.
enum Tipo {
    static let destaque = Font.system(size: 34, weight: .semibold, design: .rounded)
    static let numero = Font.system(size: 28, weight: .semibold, design: .rounded)
    static let numeroMedio = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let numeroPequeno = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let titulo = Font.system(size: 15, weight: .semibold)
    static let corpo = Font.system(size: 12.5)
    static let rotulo = Font.system(size: 10, weight: .semibold)
}

extension View {
    /// O rótulo pequeno em caixa alta em cima de cada widget ("AGORA", "PRÓXIMO").
    /// Com `cor`, o rótulo leva a cor do assunto (a capa, o calendário).
    func estiloRotulo(_ cor: Color? = nil) -> some View {
        font(Tipo.rotulo).tracking(0.7).textCase(.uppercase).lineLimit(1)
            .foregroundStyle(cor.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
    }

    /// O fundo de um cartão de conteúdo: um preenchimento claro, não vidro. O HIG deixa o Liquid Glass para os
    /// controles; sobre o preto o vidro não tem cor atrás para refletir e virava uma placa cinza, e sobre a ilha de
    /// vidro seria vidro sobre vidro. Com `cor`, o canto de cima à esquerda tinge com o assunto (a capa, o calendário).
    /// `realce`: o cursor está em cima.
    /// Com `id` e `espaco`, o fundo cresce até o do mesmo id quando um item expande ou recolhe (`matchedGeometryEffect`).
    func cartao(cor: Color? = nil, raio: CGFloat = Geometria.raioDoCartao, realce: Bool = false,
                id: String? = nil, em espaco: Namespace.ID? = nil) -> some View {
        background {
            if let id, let espaco {
                FundoDoCartao(cor: cor, raio: raio, realce: realce).matchedGeometryEffect(id: id, in: espaco, properties: .frame)
            } else {
                FundoDoCartao(cor: cor, raio: raio, realce: realce)
            }
        }
    }

    /// O vidro de verdade, só para controles (a pílula da aba, um botão por cima do conteúdo).
    func vidroDeControle(raio: CGFloat = Geometria.raioDoCartao) -> some View {
        glassEffect(.regular.tint(.white.opacity(0.08)), in: .rect(cornerRadius: raio, style: .continuous))
    }

    /// Guarda qual cartão está sob o cursor, para o realce (sem `@State`, o estado mora na `EstadoIlha`).
    func realce(_ id: String, _ estado: EstadoIlha) -> some View {
        onHover { dentro in
            if dentro { estado.cartaoSobCursor = id } else if estado.cartaoSobCursor == id { estado.cartaoSobCursor = nil }
        }
    }
}

struct FundoDoCartao: View {
    let cor: Color?
    let raio: CGFloat
    let realce: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: raio, style: .continuous)
        ZStack {
            forma.fill(.white.opacity(realce ? 0.11 : 0.07))
            if let cor {
                forma.fill(RadialGradient(colors: [cor.opacity(realce ? 0.5 : 0.42), cor.opacity(0.1), .clear],
                                          center: .topLeading, startRadius: 0, endRadius: 360))
            }
        }
        .animation(Movimento.rapido, value: realce)
    }
}

/// Os botões da ilha encolhem um pouco ao clicar: sem isso, o clique num painel que não vira key parecia não pegar.
struct EstiloBotao: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(Movimento.rapido, value: configuration.isPressed)
    }
}

/// Um toque no trackpad ao expandir ou recolher. Só se sente com o dedo num trackpad Force Touch, e a Apple pede que
/// seja resposta a algo que a pessoa fez, nunca um alerta.
enum Haptico {
    static func tocar() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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
