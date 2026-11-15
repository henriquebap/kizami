import SwiftUI

/// A forma preta presa ao topo. Sem atividade, ela encolhe para o tamanho do notch e some atrás dele
/// (em tela sem notch, a largura vai a 0).
struct IlhaView: View {
    let estado: EstadoIlha
    let mural: Mural

    var body: some View {
        let g = estado.geometria
        let vazia = mural.atividades.isEmpty
        let tamanho = vazia ? g.notch : (estado.aberta ? g.aberta : g.compacta)
        let forma = UnevenRoundedRectangle(bottomLeadingRadius: estado.aberta ? 24 : 10,
                                           bottomTrailingRadius: estado.aberta ? 24 : 10)
        ZStack(alignment: .top) {
            forma.fill(.black)
            if estado.aberta {
                Lista(atividades: mural.atividades)
                    .padding(.top, g.notch.height)  // a faixa do notch é a câmera: a lista começa abaixo dela
                    .transition(.opacity)
            } else if let destaque = mural.destaque {
                Compacta(destaque: destaque, total: mural.atividades.count)
                    .frame(height: g.notch.height)
                    .transition(.opacity)
            }
        }
        .frame(width: tamanho.width, height: tamanho.height)
        .clipShape(forma)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .animation(.bouncy(duration: 0.4), value: estado.aberta)
        .animation(.bouncy(duration: 0.4), value: vazia)
        .animation(.smooth(duration: 0.25), value: mural.destaque?.id)
    }
}

/// Fechada: o ícone na asa esquerda e, na direita, um ponto (uma atividade) ou quantas há.
private struct Compacta: View {
    let destaque: Atividade
    let total: Int

    var body: some View {
        HStack(spacing: 0) {
            Icone(atividade: destaque)
                .frame(width: Geometria.asa)
            Spacer(minLength: 0)
            Group {
                if total > 1 {
                    Text(verbatim: "\(total)").font(.caption.weight(.bold)).monospacedDigit()
                } else {
                    Circle().fill(cor(destaque)).frame(width: 7, height: 7)
                }
            }
            .frame(width: Geometria.asa)
        }
    }
}

/// Aberta: as três mais recentes; com mais de três, duas e a linha "mais N" (três linhas e o "mais" não cabem na altura).
private struct Lista: View {
    let atividades: [Atividade]

    var body: some View {
        let visiveis = atividades.count > 3 ? 2 : 3
        VStack(alignment: .leading, spacing: 6) {
            ForEach(atividades.prefix(visiveis)) { atividade in
                HStack(spacing: 10) {
                    Icone(atividade: atividade).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        // verbatim: o texto vem de fora e não pode virar Markdown nem chave de tradução.
                        Text(verbatim: atividade.titulo).font(.callout.weight(.semibold))
                        if let detalhe = atividade.detalhe {
                            Text(verbatim: detalhe).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    if let chegada = atividade.chegada {
                        Text(chegada, style: .relative).font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 32)
            }
            if atividades.count > visiveis {
                Text(String(localized: "mais \(atividades.count - visiveis)"))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 32)  // alinhado com os títulos, depois da coluna dos ícones
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct Icone: View {
    let atividade: Atividade

    var body: some View {
        Image(systemName: atividade.simbolo ?? "bell.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(cor(atividade))
            .symbolEffect(.pulse, options: .repeat(2), value: atividade.chegada)
    }
}

private func cor(_ atividade: Atividade) -> Color {
    switch atividade.cor {
    case "vermelho": .red
    case "laranja": .orange
    case "amarelo": .yellow
    case "verde": .green
    case "azul": .blue
    case "roxo": .purple
    case "rosa": .pink
    case "cinza": .gray
    default: .white
    }
}
