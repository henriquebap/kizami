import SwiftUI

/// As sessões do Claude Code na ilha aberta, uma por linha, as que pedem atenção primeiro.
/// O clique traz para frente o app onde a sessão roda.
struct SecaoClaude: View {
    let sessoes: SessoesClaude

    var body: some View {
        VStack(alignment: .leading, spacing: Geometria.espacoLinha) {
            ForEach(sessoes.sessoes.prefix(Geometria.maximoSessoes)) { sessao in
                Button { sessoes.focar(sessao) } label: { LinhaClaude(sessao: sessao) }
                    .buttonStyle(.plain)
                    .transition(.blurReplace)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct LinhaClaude: View {
    let sessao: SessaoClaude

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: simbolo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(cor)
                .symbolEffect(.pulse, isActive: sessao.estado == .precisaDeVoce)
                .symbolEffect(.rotate, isActive: sessao.estado == .trabalhando)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: sessao.pasta).font(.callout.weight(.semibold))  // nome de pasta é dado de fora
                Text(rotulo).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Text(sessao.desde, style: .relative).font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
        }
        .frame(height: Geometria.alturaLinha)
        .contentShape(Rectangle())  // o espaço entre o nome e o tempo também recebe o clique
    }

    private var simbolo: String {
        switch sessao.estado {
        case .precisaDeVoce: "exclamationmark.bubble.fill"
        case .trabalhando: "circle.dotted"
        case .pronta: "checkmark.circle.fill"
        }
    }

    private var cor: Color {
        switch sessao.estado {
        case .precisaDeVoce: .orange
        case .trabalhando: .blue
        case .pronta: .green
        }
    }

    private var rotulo: String {
        switch sessao.estado {
        case .precisaDeVoce: String(localized: "precisa de você")
        case .trabalhando: String(localized: "trabalhando")
        case .pronta: String(localized: "pronta")
        }
    }
}
