import Foundation

// Placar ao vivo: leitura do scoreboard da ESPN (com a forma da resposta real), a janela de consulta e a linha da ilha.
@MainActor func testarPlacar() {
    func utc(_ texto: String) -> Date { ESPN.data(texto)! }

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
    conferir("em jogo: lido", aoVivo, Placar(eventoId: "401873065", casa: "BAL", visitante: "LAC", pontosCasa: 13, pontosVisitante: 20,
                                            situacao: "End of 3rd", encerrado: false,
                                            link: URL(string: "https://www.espn.com/nfl/game?gameId=401873065")))
    conferir("texto: visitante primeiro, como o @ da ESPN", aoVivo?.texto, "LAC 20–13 BAL")
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
    conferir("F1 não tem placar", Placar.idESPN(corrida), nil)
    conferir("o placar é do evento", aoVivo?.eDo(jogo), true)
    let agora = utc("2026-11-17T03:30Z")
    conferir("em jogo: só o da ESPN na janela", Placar.emJogo([proximoJogo, corrida, jogo], agora: agora, encerrados: []).map(\.id), [jogo.id])
    conferir("em jogo: o encerrado sai", Placar.emJogo([jogo], agora: agora, encerrados: ["401873065"]), [])
    conferir("linha da ilha: o jogo ao vivo no lugar do próximo da mesma fonte",
             Placar.comAoVivo([proximoJogo], eventos: [jogo, proximoJogo], aoVivo: aoVivo).map(\.id), [jogo.id])
    conferir("linha da ilha: sem jogo ao vivo, igual",
             Placar.comAoVivo([proximoJogo], eventos: [jogo, proximoJogo], aoVivo: nil).map(\.id), [proximoJogo.id])
    conferir("URL do scoreboard: o dia do início em Nova York (01:15Z é 16/11 lá)",
             Placar.url(esporte: "football", liga: "nfl", inicio: jogo.inicio)?.absoluteString,
             "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?dates=20261116")
}
