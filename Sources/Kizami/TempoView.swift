import SwiftUI

/// O widget do tempo: a cidade, a temperatura grande com o símbolo e, embaixo, uma informação só. Com chuva provável,
/// a chance de chuva, que é o que muda o que a pessoa faz (levar guarda-chuva); sem, a máxima e a mínima. Com chuva
/// chegando na próxima hora, a hora dela vence as duas: é a única coisa que pede ação agora. O resto fica na dica.
struct WidgetTempo: View {
    let tempo: Tempo
    let estado: EstadoIlha
    /// A partir daqui a chuva toma o lugar da máxima e da mínima.
    private static let chuvaProvavel = 50

    var body: some View {
        if let previsao = tempo.previsao {
            Quadro(id: "tempo", estado: estado) {
                // verbatim: a cidade é a que a pessoa digitou.
                Cabeca(rotulo: tempo.local.map { Text(verbatim: $0) } ?? Text("Agora"))
                Valor {
                    Text(verbatim: Previsao.graus(previsao.temperatura))
                    Spacer(minLength: 0)
                    Image(systemName: previsao.simbolo).symbolRenderingMode(.multicolor).font(.system(size: 20))
                }
                // Por minuto: o guarda-chuva com a hora sai quando ela passa, sem esperar a próxima previsão.
                TimelineView(.everyMinute) { _ in Detalhe { detalhe(previsao) } }
            }
            .help(dica(previsao))
        }
    }

    /// A hora da chuva só enquanto ela ainda não chegou: depois a previsão seguinte já diz que está chovendo.
    private func chuvaChegando(_ previsao: Previsao) -> Date? {
        previsao.chuvaAs.flatMap { $0 > .now ? $0 : nil }
    }

    @ViewBuilder private func detalhe(_ previsao: Previsao) -> some View {
        if let chega = chuvaChegando(previsao) {
            Image(systemName: "umbrella.fill")
            Text(chega, format: .dateTime.hour().minute())
        } else if let chuva = previsao.chuva, chuva >= Self.chuvaProvavel {
            Image(systemName: "drop.fill")
            Text(verbatim: "\(chuva)%")
        } else {
            Text(verbatim: "↑\(Previsao.graus(previsao.maxima)) ↓\(Previsao.graus(previsao.minima))")
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
