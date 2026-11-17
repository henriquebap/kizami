import SwiftUI

/// O tempo à direita da faixa "Hoje": o símbolo, a data e a temperatura agora e, embaixo, uma informação só.
/// Embaixo cabe pouco (~60 pt em caption2): com chuva provável, a chance de chuva, que é o que muda o que a
/// pessoa faz (levar guarda-chuva); sem, a máxima e a mínima, que dizem como vai ser o resto do dia.
/// Com chuva chegando na próxima hora, a hora dela vence as duas: é a única coisa que pede ação agora.
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
                // Por minuto: o guarda-chuva com a hora sai quando ela passa, e a data vira à meia-noite, sem esperar
                // a próxima previsão.
                TimelineView(.everyMinute) { contexto in
                    VStack(alignment: .trailing, spacing: 0) {
                        // A data na linha da temperatura, e não na de baixo: em cima sobra largura (a temperatura é
                        // mais curta que a máxima e a mínima), então o chip cresce menos e a agenda perde menos.
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            // Do idioma do Mac: "ter., 17 de nov." ou "Tue, Nov 17".
                            Text(contexto.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(verbatim: "·").font(.caption).foregroundStyle(.tertiary)
                            Text(verbatim: Previsao.graus(previsao.temperatura))
                                .font(.system(size: 17, weight: .semibold))
                        }
                        detalhe(previsao)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
            }
            .lineLimit(1)
            .foregroundStyle(.white)
            // Medido com o `ImageRenderer`: 149 pt com "ter., 17 de nov. · 24°" e o sol, 159 com "-12°" e o símbolo
            // mais largo (em inglês, 133 a 143). O `LinhaHoje` não deixa o tempo encolher: quem cede é a agenda,
            // que dos 312 pt da faixa fica com ~155 (antes, 200).
            .frame(maxWidth: 160, maxHeight: Geometria.alturaHoje, alignment: .trailing)
            .help(dica(previsao))
        }
    }

    /// A hora da chuva só enquanto ela ainda não chegou: depois a previsão seguinte já diz que está chovendo.
    private func chuvaChegando(_ previsao: Previsao) -> Date? {
        previsao.chuvaAs.flatMap { $0 > .now ? $0 : nil }
    }

    @ViewBuilder private func detalhe(_ previsao: Previsao) -> some View {
        if let chega = chuvaChegando(previsao) {
            HStack(spacing: 2) {
                Image(systemName: "umbrella.fill")
                Text(chega, format: .dateTime.hour().minute())
            }
        } else if let chuva = previsao.chuva, chuva >= Self.chuvaProvavel {
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
            chuvaChegando(previsao).map(Tempo.tituloChuva),
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
