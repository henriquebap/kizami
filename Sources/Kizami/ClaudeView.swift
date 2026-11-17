import SwiftUI

extension EstadoClaude {
    var simbolo: String {
        switch self {
        case .precisaDeVoce: "exclamationmark.bubble.fill"
        case .trabalhando: "circle.dotted"
        case .pronta: "checkmark.circle.fill"
        }
    }

    var cor: Color {
        switch self {
        case .precisaDeVoce: .orange
        case .trabalhando: .blue
        case .pronta: .green
        }
    }

    var rotulo: String {
        switch self {
        case .precisaDeVoce: String(localized: "precisa de você")
        case .trabalhando: String(localized: "trabalhando")
        case .pronta: String(localized: "pronta")
        }
    }
}

/// Uma sessão parada esperando a pessoa, em destaque: é a única coisa da ilha que trava um trabalho até alguém agir.
/// O clique (no cartão ou no Abrir) traz a sessão para frente; as outras sessões viram pílulas embaixo.
struct CartaoClaude: View {
    let sessoes: SessoesClaude

    var body: some View {
        if let sessao = sessoes.sessoes.first(where: { $0.estado == .precisaDeVoce }) {
            let outras = sessoes.sessoes.filter { $0.id != sessao.id }.prefix(3)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: EstadoClaude.precisaDeVoce.simbolo)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, value: sessao.desde)  // uma vez, quando passa a pedir; nada animando parado
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.orange.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Claude Code").estiloRotulo(.orange)
                        // verbatim: o nome da pasta vem de fora.
                        Text(verbatim: String(localized: "\(sessao.pasta) precisa de você")).font(Tipo.titulo)
                        (Text("esperando há ") + Text(sessao.desde, style: .relative))
                            .font(Tipo.corpo).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { sessoes.focar(sessao) } label: {
                        Label("Abrir", systemImage: "arrow.up.right")
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(.orange))
                            .foregroundStyle(.black.opacity(0.85))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(EstiloBotao())
                    .fixedSize()
                }
                if !outras.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(outras) { outra in
                            Button { sessoes.focar(outra) } label: { PilulaDeSessao(sessao: outra) }
                                .buttonStyle(EstiloBotao())
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cartao(cor: .orange, raio: Geometria.raioDoWidget)
            .contentShape(.rect)
            .onTapGesture { sessoes.focar(sessao) }
        }
    }
}

private struct PilulaDeSessao: View {
    let sessao: SessaoClaude

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(sessao.estado.cor).frame(width: 7, height: 7)
            Text(verbatim: sessao.pasta).font(.system(size: 11.5, weight: .medium))  // nome de pasta é dado de fora
            Text(verbatim: sessao.estado.rotulo).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

/// As sessões do Claude num quadrado: quantas são, um ponto por estado e as pastas. Clique: a que pede mais atenção.
struct WidgetSessoes: View {
    let sessoes: SessoesClaude
    let estado: EstadoIlha

    var body: some View {
        let lista = sessoes.sessoes
        Quadro(id: "sessoes", estado: estado, acao: lista.first.map { primeira in { sessoes.focar(primeira) } }) {
            Cabeca(rotulo: Text(verbatim: "Claude"), simbolo: "sparkles", cor: .orange)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(lista.count)").font(Tipo.numero).monospacedDigit()
                Text(lista.count == 1 ? "sessão" : "sessões").font(Tipo.corpo).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(lista.prefix(4)) { sessao in
                    Circle().fill(sessao.estado.cor).frame(width: 7, height: 7)
                        .help(Text(verbatim: "\(sessao.pasta): \(sessao.estado.rotulo)"))
                }
                Text(verbatim: lista.map(\.pasta).joined(separator: ", "))
                    .font(Tipo.corpo).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
