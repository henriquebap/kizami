import SwiftUI

/// Os estados da forma, do menor para o maior.
private enum Forma: Equatable {
    case escondida, compacta, aviso, aberta

    var orelha: CGFloat { self == .aberta ? 10 : Geometria.orelha }
    var raio: CGFloat {
        switch self {
        case .escondida, .compacta: 14
        case .aviso: 20
        case .aberta: 30
        }
    }
}

/// A forma preta presa ao topo. Sem atividade, encolhe para o tamanho do notch e some atrás dele
/// (em tela sem notch, a largura vai a 0).
struct IlhaView: View {
    let estado: EstadoIlha
    let mural: Mural

    var body: some View {
        let g = estado.geometria
        let forma: Forma = mural.atividades.isEmpty ? .escondida
            : estado.aberta ? .aberta
            : mural.novidade != nil ? .aviso
            : .compacta
        let tamanho = switch forma {
        case .escondida: g.notch
        case .compacta: g.compacta
        case .aviso: g.aviso
        case .aberta: g.aberta(linhas: mural.atividades.count)
        }
        let contorno = FormaIlha(orelha: forma.orelha, raio: forma.raio)

        ZStack(alignment: .top) {
            contorno.fill(.black)
            Group {
                switch forma {
                case .escondida:
                    EmptyView()
                case .compacta:
                    if let destaque = mural.destaque {
                        Compacta(destaque: destaque, total: mural.atividades.count)
                            .frame(height: g.notch.height)
                    }
                case .aviso:
                    if let novidade = mural.novidade {
                        LinhaDeAviso(atividade: novidade)
                            .frame(height: Geometria.alturaLinha)
                            .padding(.top, g.notch.height)  // a faixa do notch é a câmera: o texto vem abaixo
                    }
                case .aberta:
                    Lista(atividades: mural.atividades)
                        .padding(.top, g.notch.height + 8)
                }
            }
            .padding(.horizontal, forma.orelha)
            .transition(.blurReplace)
        }
        .frame(width: tamanho.width, height: tamanho.height)
        .clipShape(contorno)
        .shadow(color: .black.opacity(forma == .aberta ? 0.4 : 0), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        // Abrir com um pouco de mola, fechar sem: a ilha "cai" do notch e volta para dentro dele sem quicar.
        .animation(forma == .escondida || forma == .compacta
                   ? .spring(response: 0.34, dampingFraction: 0.92)
                   : .spring(response: 0.44, dampingFraction: 0.74), value: forma)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mural.atividades.count)
    }
}

/// O contorno do notch: orelhas côncavas no topo, que fundem a ilha com a borda da tela,
/// e cantos de baixo arredondados. Os dois raios animam entre os estados.
struct FormaIlha: Shape {
    var orelha: CGFloat
    var raio: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(orelha, raio) }
        set { orelha = newValue.first; raio = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let o = min(orelha, r.width / 4)
        let raio = max(0, min(raio, (r.width - 2 * o) / 2, r.height - o))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + o, y: r.minY + o), control: CGPoint(x: r.minX + o, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX + o, y: r.maxY), tangent2End: CGPoint(x: r.maxX - o, y: r.maxY), radius: raio)
        p.addArc(tangent1End: CGPoint(x: r.maxX - o, y: r.maxY), tangent2End: CGPoint(x: r.maxX - o, y: r.minY + o), radius: raio)
        p.addLine(to: CGPoint(x: r.maxX - o, y: r.minY + o))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - o, y: r.minY))
        p.closeSubpath()
        return p
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
                        .contentTransition(.numericText())
                } else {
                    Circle().fill(cor(destaque)).frame(width: 7, height: 7)
                }
            }
            .frame(width: Geometria.asa)
        }
    }
}

/// O aviso: ícone, título e detalhe numa linha, centrados abaixo do notch.
private struct LinhaDeAviso: View {
    let atividade: Atividade

    var body: some View {
        HStack(spacing: 8) {
            Icone(atividade: atividade)
            // verbatim: o texto vem de fora e não pode virar Markdown nem chave de tradução.
            Text(verbatim: atividade.titulo).font(.callout.weight(.semibold))
            if let detalhe = atividade.detalhe {
                Text(verbatim: detalhe).font(.callout).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
    }
}

/// Aberta: as três mais recentes; com mais de três, duas e a linha "mais N" no lugar da terceira.
private struct Lista: View {
    let atividades: [Atividade]

    var body: some View {
        let visiveis = atividades.count > Geometria.maximoLinhas ? Geometria.maximoLinhas - 1 : Geometria.maximoLinhas
        VStack(alignment: .leading, spacing: Geometria.espacoLinha) {
            ForEach(atividades.prefix(visiveis)) { atividade in
                HStack(spacing: 10) {
                    Icone(atividade: atividade).frame(width: 22)
                    VStack(alignment: .leading, spacing: 0) {
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
                .frame(height: Geometria.alturaLinha)
                .transition(.blurReplace)
            }
            if atividades.count > visiveis {
                Text(String(localized: "mais \(atividades.count - visiveis)"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: Geometria.alturaLinha)
                    .padding(.leading, 32)  // alinhado com os títulos, depois da coluna dos ícones
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct Icone: View {
    let atividade: Atividade

    var body: some View {
        Image(systemName: atividade.simbolo ?? "bell.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(cor(atividade))
            .symbolEffect(.bounce, value: atividade.chegada)
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
