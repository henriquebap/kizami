import SwiftUI

/// O tempo à direita da faixa "Hoje": o símbolo, a temperatura agora e, embaixo, uma informação só.
/// Embaixo cabe pouco (~60 pt em caption2): com chuva provável, a chance de chuva, que é o que muda o que a
/// pessoa faz (levar guarda-chuva); sem, a máxima e a mínima, que dizem como vai ser o resto do dia.
/// O resto (descrição, as duas coisas, a cidade) fica na dica.
struct ChipTempo: View {
    let tempo: Tempo
    /// A partir daqui a chuva toma o lugar da máxima e da mínima.
    private static let chuvaProvavel = 50

    var body: some View {
        if let previsao = tempo.previsao {
            HStack(spacing: 6) {
                Image(systemName: previsao.simbolo)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 20))
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: Previsao.graus(previsao.temperatura))
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                    detalhe(previsao)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(maxWidth: 110, maxHeight: Geometria.alturaHoje, alignment: .trailing)
            .help(dica(previsao))
        }
    }

    @ViewBuilder private func detalhe(_ previsao: Previsao) -> some View {
        if let chuva = previsao.chuva, chuva >= Self.chuvaProvavel {
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                Text(verbatim: "\(chuva)%")
            }
        } else {
            HStack(spacing: 1) {
                Image(systemName: "arrow.up")
                Text(verbatim: Previsao.graus(previsao.maxima))
                Image(systemName: "arrow.down").padding(.leading, 3)
                Text(verbatim: Previsao.graus(previsao.minima))
            }
        }
    }

    private func dica(_ previsao: Previsao) -> String {
        [
            previsao.descricao,
            String(localized: "máx \(Previsao.graus(previsao.maxima)) · mín \(Previsao.graus(previsao.minima))"),
            previsao.chuva.map { chuva in
                let porcento = "\(chuva)%"  // como String: um % solto na chave da tradução viraria formato
                return String(localized: "Chance de chuva: \(porcento)")
            },
            tempo.local,
        ].compactMap { $0 }.joined(separator: "\n")
    }
}
