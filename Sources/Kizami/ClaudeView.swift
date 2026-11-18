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
            VStack(alignment: .leading, spacing: Painel.espaco) {
                // verbatim: o nome da pasta vem de fora.
                LinhaDeDestaque(rotulo: Text(verbatim: "Claude Code"), corDoRotulo: .orange,
                                titulo: Text(verbatim: String(localized: "\(sessao.pasta) precisa de você")),
                                detalhe: Text("esperando há \(Text(sessao.desde, style: .relative))")) {
                    IconeDeDestaque(simbolo: EstadoClaude.precisaDeVoce.simbolo, cor: .orange)
                        .symbolEffect(.bounce, value: sessao.desde)  // uma vez, quando passa a pedir; nada animando parado
                } fim: {
                    Pilula(titulo: "Abrir", simbolo: "arrow.up.right", cor: .orange) { sessoes.focar(sessao) }
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
            .padding(Painel.folga)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cartao(cor: .orange, raio: Painel.raio)
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
            Text(verbatim: sessao.pasta)  // nome de pasta é dado de fora
            Text(verbatim: sessao.estado.rotulo).foregroundStyle(.secondary)
        }
        .font(Tipo.legenda)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: Painel.botao)
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
            Valor {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "\(lista.count)")
                    Text(lista.count == 1 ? "sessão" : "sessões").font(Tipo.corpo).foregroundStyle(.secondary)
                }
            }
            Detalhe {
                ForEach(lista.prefix(4)) { sessao in
                    Circle().fill(sessao.estado.cor).frame(width: 7, height: 7)
                        .help(Text(verbatim: "\(sessao.pasta): \(sessao.estado.rotulo)"))
                }
                Text(verbatim: lista.map(\.pasta).joined(separator: ", "))
            }
        }
    }
}
