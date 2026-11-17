import Foundation

// Placar ao vivo: leitura do scoreboard da ESPN (com a forma da resposta real), a janela de consulta e a linha da ilha.
@MainActor func testarPlacar() {
    func utc(_ texto: String) -> Date { ESPN.data(texto)! }
    let agoraFixo = utc("2026-11-17T03:30Z")

    // Scoreboard real da NFL (17/11/2026, Monday Night em andamento) e um jogo da Premier League ainda por vir, cortados.
    let real = """
        {"events":[
        {"id":"401873065","date":"2026-11-17T01:15Z","shortName":"LAC @ BAL",
         "status":{"clock":0.0,"period":3,"type":{"id":"22","name":"STATUS_END_PERIOD","state":"in","completed":false,"shortDetail":"End of 3rd"}},
         "links":[{"href":"https://www.espn.com/nfl/game?gameId=401873065"}],
         "competitions":[{"id":"401873065","competitors":[
         {"homeAway":"home","score":"13","team":{"id":"33","abbreviation":"BAL","shortDisplayName":"Ravens"}},
         {"homeAway":"away","score":"20","team":{"id":"24","abbreviation":"LAC","shortDisplayName":"Chargers"}}]}]},
        {"id":"401873052","date":"2026-11-13T01:15Z","shortName":"WSH @ NYG",
         "status":{"type":{"state":"post","completed":true,"shortDetail":"Final"}},
         "links":[{"href":"sportscenter://x-callback-url/showGame"},{"href":"https://www.espn.com/nfl/game/_/gameId/401873052/commanders-giants"}],
         "competitions":[{"id":"401873052","competitors":[
         {"homeAway":"home","score":"21","team":{"id":"19","abbreviation":"NYG"}},
         {"homeAway":"away","score":"24","team":{"id":"28","abbreviation":"WSH"}}]}]},
        {"id":"401879233","date":"2026-11-21T12:30Z","shortName":"MNC @ FUL",
         "status":{"type":{"state":"pre","completed":false,"shortDetail":"Scheduled"}},
         "competitions":[{"id":"401879233","competitors":[
         {"homeAway":"home","score":"0","team":{"id":"370","abbreviation":"FUL"}},
         {"homeAway":"away","score":"0","team":{"id":"382","abbreviation":"MNC"}}]}]},
        {"id":"9001","status":{"type":{"state":"post","completed":false,"shortDetail":"Postponed"}},
         "competitions":[{"competitors":[{"homeAway":"home","score":"0","team":{"abbreviation":"AAA"}},
         {"homeAway":"away","score":"0","team":{"abbreviation":"BBB"}}]}]},
        {"id":"9002","status":{"type":{"state":"in"}},"competitions":[{"competitors":[
         {"homeAway":"home","score":"1000","team":{"abbreviation":"AAA"}},{"homeAway":"away","score":"3","team":{"abbreviation":"BBB"}}]}]},
        {"id":"9003","status":{"type":{"state":"in"}},"competitions":[{"competitors":[
         {"homeAway":"home","score":"-1","team":{"abbreviation":"AAA"}},{"homeAway":"away","score":"3","team":{"abbreviation":"BBB"}}]}]},
        {"id":"9004","status":{"type":{"state":"in"}},"competitions":[{"competitors":[
         {"homeAway":"home","score":"1","team":{"abbreviation":"A\\u202eB"}},{"homeAway":"away","score":"3","team":{"abbreviation":"BBB"}}]}]},
        {"id":"9005","status":{"type":{"state":"in"}},"competitions":[{"competitors":[
         {"homeAway":"home","score":"1","team":{"abbreviation":"MUITOLONGA"}},{"homeAway":"away","score":"3","team":{"abbreviation":"BBB"}}]}]},
        {"id":"9006","status":{"type":{"state":"in"}},"competitions":[{"competitors":[
         {"homeAway":"home","score":"1","team":{"abbreviation":"AAA"}},{"homeAway":"home","score":"3","team":{"abbreviation":"BBB"}}]}]}
        ]}
        """
    let dados = Data(real.utf8)
    let aoVivo = Placar.ler(dados, eventoId: "401873065")
    conferir("em jogo: lido", aoVivo, Placar(eventoId: "401873065",
                                            lances: .jogo(casa: "BAL", visitante: "LAC", pontosCasa: 13, pontosVisitante: 20),
                                            situacao: "End of 3rd", encerrado: false,
                                            link: URL(string: "https://www.espn.com/nfl/game?gameId=401873065")))
    conferir("texto: visitante primeiro, como o @ da ESPN", aoVivo?.texto, "LAC 20–13 BAL")
    conferir("asa: visitante à esquerda", aoVivo.map { [$0.asa.esquerda, $0.asa.direita] }, ["LAC 20", "13 BAL"])
    let final = Placar.ler(dados, eventoId: "401873052")
    conferir("terminado: encerrado", final?.encerrado, true)
    conferir("terminado: situação", final?.situacao, "Final")
    conferir("terminado: o link https da ESPN, não o do app", final?.link,
             URL(string: "https://www.espn.com/nfl/game/_/gameId/401873052/commanders-giants"))
    conferir("ainda não começou: nil", Placar.ler(dados, eventoId: "401879233"), nil)
    conferir("adiado (post sem completed): nil, nada de \"Fim de jogo\"", Placar.ler(dados, eventoId: "9001"), nil)
    conferir("placar acima de 999: nil", Placar.ler(dados, eventoId: "9002"), nil)
    conferir("placar negativo: nil", Placar.ler(dados, eventoId: "9003"), nil)
    conferir("sigla com caractere de direção: nil", Placar.ler(dados, eventoId: "9004"), nil)
    conferir("sigla longa demais: nil", Placar.ler(dados, eventoId: "9005"), nil)
    conferir("dois em casa: nil", Placar.ler(dados, eventoId: "9006"), nil)
    conferir("evento que não está na resposta: nil", Placar.ler(dados, eventoId: "123"), nil)
    conferir("JSON quebrado: nil", Placar.ler(Data("{".utf8), eventoId: "401873065"), nil)
    conferir("página de erro: nil", Placar.ler(Data("<html>erro</html>".utf8), eventoId: "401873065"), nil)
    conferir("sem events: nil", Placar.ler(Data(#"{"leagues":[]}"#.utf8), eventoId: "401873065"), nil)

    // MARK: Janela

    let inicio = utc("2026-11-22T18:00Z")
    conferir("antes do início: não consulta", Placar.deveConsultar(inicio: inicio, agora: utc("2026-11-22T17:59Z")), false)
    conferir("no início: consulta", Placar.deveConsultar(inicio: inicio, agora: inicio), true)
    conferir("4 h depois (prorrogação): consulta", Placar.deveConsultar(inicio: inicio, agora: utc("2026-11-22T22:00Z")), true)
    conferir("5 h e 1 min depois: para", Placar.deveConsultar(inicio: inicio, agora: utc("2026-11-22T23:01Z")), false)

    // MARK: Eventos

    let jogo = EventoInteresse(id: "espn-401873065-\(Int(utc("2026-11-17T01:15Z").timeIntervalSince1970))", titulo: "Bills x Ravens",
                               inicio: utc("2026-11-17T01:15Z"), fonte: .bills)
    let proximoJogo = EventoInteresse(id: "espn-401873100-1", titulo: "Bills @ Jets", inicio: utc("2026-11-23T18:00Z"), fonte: .bills)
    let corrida = EventoInteresse(id: "f1-401839137-1", titulo: "Las Vegas", inicio: utc("2026-11-17T01:00Z"), fonte: .f1)
    conferir("id da ESPN dentro do id do evento", Placar.idESPN(jogo), "401873065")
    conferir("F1: o id da corrida", Placar.idESPN(corrida), "401839137")
    conferir("ICS não tem placar", Placar.idESPN(EventoInteresse(id: "ics-1-abc", titulo: "x", inicio: agoraFixo,
                                                                fonte: .ics(url: URL(string: "https://exemplo.com/a.ics")!))), nil)
    conferir("o placar é do evento", aoVivo?.eDo(jogo), true)
    let agora = utc("2026-11-17T03:30Z")
    conferir("em jogo: os da ESPN na janela, o que começou antes primeiro",
             Placar.emJogo([proximoJogo, jogo, corrida], agora: agora, encerrados: []).map(\.id), [corrida.id, jogo.id])
    conferir("em jogo: o encerrado sai", Placar.emJogo([jogo], agora: agora, encerrados: ["401873065"]), [])
    conferir("linha da ilha: o jogo ao vivo no lugar do próximo da mesma fonte",
             Placar.comAoVivo([proximoJogo], eventos: [jogo, proximoJogo], aoVivo: aoVivo.map { [$0] } ?? []).map(\.id), [jogo.id])
    conferir("linha da ilha: sem jogo ao vivo, igual",
             Placar.comAoVivo([proximoJogo], eventos: [jogo, proximoJogo], aoVivo: []).map(\.id), [proximoJogo.id])

    // MARK: Dois ao vivo

    let outro = EventoInteresse(id: "espn-401879300-1", titulo: "Flamengo x Palmeiras", inicio: utc("2026-11-17T00:30Z"),
                                fonte: .espnTime(esporte: "soccer", liga: "bra.1", time: "819", nome: "Flamengo"))
    let terceiro = EventoInteresse(id: "espn-401879301-1", titulo: "Lakers x Celtics", inicio: utc("2026-11-17T02:00Z"),
                                   fonte: .espnTime(esporte: "basketball", liga: "nba", time: "13", nome: "Lakers"))
    func placar(_ id: String, _ pontos: Int, encerrado: Bool = false) -> Placar {
        Placar(eventoId: id, lances: .jogo(casa: "AAA", visitante: "BBB", pontosCasa: pontos, pontosVisitante: 0),
               situacao: "", encerrado: encerrado, link: nil)
    }
    let naJanela = Placar.emJogo([jogo, terceiro, outro], agora: agora, encerrados: [])
    conferir("dois ao vivo: o que começou antes primeiro, no máximo dois",
             Placar.aoVivo(lidos: [placar("401879301", 1), placar("401873065", 2), placar("401879300", 3)], consultados: [], antes: [],
                           naJanela: naJanela).map(\.eventoId), ["401879300", "401873065"])
    conferir("dois ao vivo: a liga que não respondeu fica com o placar de antes",
             Placar.aoVivo(lidos: [placar("401873065", 7)], consultados: [], antes: [placar("401879300", 3), placar("401873065", 2)],
                           naJanela: naJanela), [placar("401879300", 3), placar("401873065", 7)])
    conferir("dois ao vivo: o que acabou sai e o terceiro entra",
             Placar.aoVivo(lidos: [placar("401879300", 3, encerrado: true), placar("401879301", 1)],
                           consultados: [], antes: [placar("401879300", 2), placar("401873065", 2)], naJanela: naJanela).map(\.eventoId),
             ["401873065", "401879301"])
    conferir("dois ao vivo: a liga respondeu sem o placar (jogo suspenso): sai, não fica o de antes",
             Placar.aoVivo(lidos: [placar("401873065", 7)], consultados: ["401879300", "401873065"],
                           antes: [placar("401879300", 3), placar("401873065", 2)], naJanela: naJanela).map(\.eventoId),
             ["401873065"])
    conferir("dois ao vivo: fora da janela, sai mesmo com placar de antes",
             Placar.aoVivo(lidos: [], consultados: [], antes: [placar("401879300", 2)], naJanela: [jogo]), [])
    conferir("dois ao vivo: seguir os dois times do mesmo jogo dá um jogo só",
             Placar.emJogo([jogo, EventoInteresse(id: jogo.id, titulo: "Ravens x Chargers", inicio: jogo.inicio,
                                                  fonte: .espnTime(esporte: "football", liga: "nfl", time: "33", nome: "Ravens"))],
                           agora: agora, encerrados: []).count, 1)
    let doisJogos = [placar("401879300", 3), placar("401873065", 2)]
    conferir("linha da ilha: os dois ao vivo, cada um no lugar do próximo da sua fonte",
             Placar.comAoVivo([proximoJogo, corrida], eventos: [jogo, outro, proximoJogo, corrida], aoVivo: doisJogos).map(\.id),
             [outro.id, jogo.id, corrida.id])

    // MARK: A vez na asa

    let t0 = Date(timeIntervalSinceReferenceDate: 8 * 1000)
    conferir("asa: sem nenhum, nil", Placar.daVez([], agora: t0), nil)
    conferir("asa: um só fica parado", Placar.daVez([doisJogos[0]], agora: t0.addingTimeInterval(8))?.eventoId, "401879300")
    conferir("asa: dois, um de cada vez", [0, 7.9, 8, 15.9, 16].map { Placar.daVez(doisJogos, agora: t0.addingTimeInterval($0))?.eventoId ?? "" },
             ["401879300", "401879300", "401873065", "401873065", "401879300"])
    conferir("URL do scoreboard: o dia do início em Nova York (01:15Z é 16/11 lá)",
             Placar.url(esporte: "football", liga: "nfl", inicio: jogo.inicio)?.absoluteString,
             "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?dates=20261116")

    // MARK: F1

    // Forma do scoreboard real da F1 (São Paulo, 08/11/2026, já terminada), cortada: o fim de semana é um evento com
    // uma competição por sessão; na corrida, cada `competitor` é um piloto com `order` e `athlete.shortName`, sem sigla.
    func corridaJSON(estado: String, completo: Bool, pilotos: String, tipo: String = "Race") -> Data {
        Data("""
            {"events":[{"id":"600057448","shortName":"MSC Cruises São Paulo GP",
             "status":{"type":{"state":"\(estado)","completed":false}},
             "links":[{"href":"https://www.espn.com/f1/race/_/id/600057448"}],
             "competitions":[
              {"id":"401839131","type":{"abbreviation":"Qual"},"status":{"type":{"state":"post","completed":true,"shortDetail":"Final"}},
               "competitors":[{"order":1,"athlete":{"shortName":"K. Antonelli"}}]},
              {"id":"401839132","type":{"abbreviation":"\(tipo)"},
               "status":{"type":{"state":"\(estado)","completed":\(completo),"shortDetail":"\(completo ? "Final" : "Lap 23")"}},
               "competitors":[\(pilotos)]}]}]}
            """.utf8)
    }
    let grid = """
        {"id":"5579","type":"athlete","order":1,"winner":true,"athlete":{"fullName":"Lando Norris","displayName":"Lando Norris","shortName":"L. Norris"}},
        {"id":"4665","type":"athlete","order":2,"athlete":{"shortName":"M. Verstappen"}},
        {"id":"5790","type":"athlete","order":3,"athlete":{"shortName":"I. Hadjar"}},
        {"id":"9999","type":"athlete","order":4,"athlete":{"shortName":"N. Hülkenberg"}}
        """
    let emCorrida = Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: grid), corridaId: "401839132")
    conferir("F1: a ponta da corrida", emCorrida,
             Placar(eventoId: "401839132", lances: .corrida(["NOR", "VER", "HAD"]), situacao: "Lap 23", encerrado: false,
                    link: URL(string: "https://www.espn.com/f1/race/_/id/600057448")))
    conferir("F1: texto", emCorrida?.texto, "1 NOR · 2 VER · 3 HAD")
    conferir("F1: asa", emCorrida.map { [$0.asa.esquerda, $0.asa.direita] }, ["1 NOR", "2 VER"])
    conferir("F1: terminada, com o vencedor primeiro",
             Placar.lerCorrida(corridaJSON(estado: "post", completo: true, pilotos: grid), corridaId: "401839132")
                .map { [$0.texto, $0.situacao, "\($0.encerrado)"] }, ["1 NOR · 2 VER · 3 HAD", "Final", "true"])
    conferir("F1: fora de ordem na resposta, ordenada por order",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: """
                 {"order":3,"athlete":{"shortName":"I. Hadjar"}},{"order":1,"athlete":{"shortName":"L. Norris"}},
                 {"order":2,"athlete":{"shortName":"M. Verstappen"}}
                 """), corridaId: "401839132")?.texto, "1 NOR · 2 VER · 3 HAD")
    conferir("F1: dois pilotos só, os dois",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: """
                 {"order":1,"athlete":{"shortName":"L. Norris"}},{"order":2,"athlete":{"shortName":"M. Verstappen"}}
                 """), corridaId: "401839132")?.texto, "1 NOR · 2 VER")
    let soUm = Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: #"{"order":1,"athlete":{"shortName":"L. Norris"}}"#),
                                 corridaId: "401839132")
    conferir("F1: um piloto só, a asa direita vazia", soUm.map { [$0.asa.esquerda, $0.asa.direita] }, ["1 NOR", ""])
    conferir("F1: sem pilotos ainda: nil",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: ""), corridaId: "401839132"), nil)
    conferir("F1: sem o 1º (buraco na ponta): nil",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: """
                 {"order":2,"athlete":{"shortName":"M. Verstappen"}},{"order":3,"athlete":{"shortName":"I. Hadjar"}}
                 """), corridaId: "401839132"), nil)
    conferir("F1: posição repetida: nil",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: """
                 {"order":1,"athlete":{"shortName":"L. Norris"}},{"order":1,"athlete":{"shortName":"M. Verstappen"}}
                 """), corridaId: "401839132"), nil)
    conferir("F1: um nome estranho na ponta recusa tudo, não corta",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: """
                 {"order":1,"athlete":{"shortName":"L. Norris"}},{"order":2,"athlete":{"shortName":"M. Ver\\u202estappen"}}
                 """), corridaId: "401839132"), nil)
    conferir("F1: sem order: nil",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: #"{"athlete":{"shortName":"L. Norris"}}"#),
                               corridaId: "401839132"), nil)
    conferir("F1: ainda não largou: nil", Placar.lerCorrida(corridaJSON(estado: "pre", completo: false, pilotos: grid), corridaId: "401839132"), nil)
    conferir("F1: sessão que não é a corrida: nil",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: grid, tipo: "FP1"), corridaId: "401839132"), nil)
    conferir("F1: a classificação não é a corrida, mesmo com o id dela: nil",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: grid), corridaId: "401839131"), nil)
    conferir("F1: corrida que não está na resposta: nil",
             Placar.lerCorrida(corridaJSON(estado: "in", completo: false, pilotos: grid), corridaId: "123"), nil)
    conferir("F1: JSON quebrado: nil", Placar.lerCorrida(Data("{".utf8), corridaId: "401839132"), nil)
    conferir("F1: siglas do grid real de 2026, acento fora",
             ["L. Norris", "N. Hülkenberg", "S. Pérez", "R. Câmara", "K. Antonelli", "G. Bortoleto", "Z. Guanyu", "N. de Vries"]
                .map { Placar.siglaPiloto($0) ?? "nil" },
             ["NOR", "HUL", "PER", "CAM", "ANT", "BOR", "GUA", "DEV"])
    conferir("F1: nomes estranhos recusados",
             ["Norris", "Lando Norris", "LN. Norris", "1. Norris", "L. N0rris", "L. No", "L. Nor\u{202E}ris", "L. Norris!",
              "L. " + String(repeating: "a", count: 25), "", "L. "]
                .map { Placar.siglaPiloto($0) ?? "nil" },
             Array(repeating: "nil", count: 11))
    conferir("F1: o fim da atividade", emCorrida?.fim, "Fim da corrida")
    conferir("jogo: o fim da atividade", aoVivo?.fim, "Fim de jogo")
}
