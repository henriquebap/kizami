import Foundation

// Interesses: leitura da ESPN (com a forma das respostas reais), o leitor de ICS, a agenda de lembretes e a rede.
@MainActor func testarInteresses() {
    func utc(_ texto: String) -> Date { ESPN.data(texto)! }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/Sao_Paulo")!  // sem horário de verão desde 2019: o teste não muda com a época
    cal.locale = Locale(identifier: "pt_BR")

    // MARK: ESPN

    conferir("data sem segundos", ESPN.data("2026-11-22T18:00Z"), Date(timeIntervalSince1970: 1_795_370_400))
    conferir("data com segundos", ESPN.data("2026-11-22T18:00:00Z"), Date(timeIntervalSince1970: 1_795_370_400))
    conferir("data quebrada", ESPN.data("amanhã"), nil)

    // Agenda real dos Bills (16/11/2026), cortada: um jogo que já foi, um em casa, um fora e um sem hora (TBD).
    let agendaReal = """
        {"events":[
        {"id":"401873054","date":"2026-11-15T18:00Z","shortName":"BUF @ NYJ","timeValid":true,"competitions":[{"id":"401873054",
         "date":"2026-11-15T18:00Z","competitors":[
         {"homeAway":"home","team":{"id":"20","abbreviation":"NYJ","displayName":"New York Jets","shortDisplayName":"Jets"}},
         {"homeAway":"away","team":{"id":"2","abbreviation":"BUF","displayName":"Buffalo Bills","shortDisplayName":"Bills"}}],
         "status":{"type":{"state":"post","completed":true}}}]},
        {"id":"401873070","date":"2026-11-22T18:00Z","shortName":"MIA @ BUF","timeValid":true,"competitions":[{"id":"401873070",
         "date":"2026-11-22T18:00Z","competitors":[
         {"homeAway":"home","team":{"id":"2","abbreviation":"BUF","displayName":"Buffalo Bills","shortDisplayName":"Bills"}},
         {"homeAway":"away","team":{"id":"15","abbreviation":"MIA","displayName":"Miami Dolphins","shortDisplayName":"Dolphins"}}],
         "status":{"type":{"state":"pre","completed":false}}}]},
        {"id":"401873105","date":"2026-12-06T21:25Z","shortName":"BUF @ NE","timeValid":true,"competitions":[{"id":"401873105",
         "date":"2026-12-06T21:25Z","competitors":[
         {"homeAway":"home","team":{"id":"17","abbreviation":"NE","displayName":"New England Patriots","shortDisplayName":"Patriots"}},
         {"homeAway":"away","team":{"id":"2","abbreviation":"BUF","displayName":"Buffalo Bills","shortDisplayName":"Bills"}}],
         "status":{"type":{"state":"pre","completed":false}}}]},
        {"id":"401873181","date":"2027-01-10T05:00Z","shortName":"NYJ @ BUF","timeValid":false,"competitions":[{"id":"401873181",
         "date":"2027-01-10T05:00Z","competitors":[
         {"homeAway":"home","team":{"id":"2","abbreviation":"BUF","displayName":"Buffalo Bills","shortDisplayName":"Bills"}},
         {"homeAway":"away","team":{"id":"20","abbreviation":"NYJ","displayName":"New York Jets","shortDisplayName":"Jets"}}],
         "status":{"type":{"state":"pre","completed":false}}}]}
        ],"team":{"id":"2","abbreviation":"BUF"}}
        """
    let jogos = ESPN.jogos(de: Data(agendaReal.utf8), time: "2", fonte: .bills) ?? []
    conferir("jogos: sem o que já foi nem o sem hora", jogos.map { String($0.id.prefix(14)) }, ["espn-401873070", "espn-401873105"])
    conferir("o início entra no id: jogo que muda de horário ganha lembretes novos", jogos.first?.id,
             "espn-401873070-\(Int(utc("2026-11-22T18:00Z").timeIntervalSince1970))")
    conferir("em casa: Bills x Dolphins", jogos.first?.titulo, "Bills x Dolphins")
    conferir("fora: Bills @ Patriots", jogos.last?.titulo, "Bills @ Patriots")
    conferir("início do jogo", jogos.first?.inicio, utc("2026-11-22T18:00Z"))
    conferir("página do jogo: o link https da ESPN, não o do app",
             ESPN.pagina([ESPN.Link(href: "sportscenter://x-callback-url/showGame"), ESPN.Link(href: "https://www.espn.com/nfl/game/_/gameId/1")]),
             URL(string: "https://www.espn.com/nfl/game/_/gameId/1"))
    conferir("página de outro host não vale", ESPN.pagina([ESPN.Link(href: "https://espn.com.evil.example/x")]), nil as URL?)
    conferir("JSON quebrado: nil, a lista de antes fica", ESPN.jogos(de: Data("{".utf8), time: "2", fonte: .bills), nil)
    conferir("sem events: nil", ESPN.jogos(de: Data(#"{"team":{}}"#.utf8), time: "2", fonte: .bills), nil)
    conferir("adversário indefinido (time sem id) não derruba a agenda: o jogo fica",
             ESPN.jogos(de: Data(#"{"events":[{"id":"9","date":"2026-12-01T18:00Z","competitions":[{"competitors":[{"team":{}},{"team":{"id":"2"}}]}]}]}"#.utf8),
                        time: "2", fonte: .bills)?.count, 1)

    // Placar real da F1 (16/11/2026), cortado: treino, classificação e corrida de Las Vegas.
    let f1Real = """
        {"events":[{"id":"600057449","date":"2026-11-20T00:30Z","name":"Heineken Las Vegas Grand Prix",
        "shortName":"Heineken Las Vegas GP","competitions":[
        {"id":"401839133","date":"2026-11-20T00:30Z","type":{"id":"1","abbreviation":"FP1"},"status":{"type":{"completed":false}}},
        {"id":"401839136","date":"2026-11-21T04:00Z","type":{"id":"2","abbreviation":"Qual"},"status":{"type":{"completed":false}}},
        {"id":"401839137","date":"2026-11-22T04:00Z","type":{"id":"3","abbreviation":"Race"},"status":{"type":{"completed":false}}}]}]}
        """
    let corridas = ESPN.corridas(de: Data(f1Real.utf8)) ?? []
    conferir("F1: o fim de semana todo; a corrida com o id do placar, as sessões com f1s", corridas.map(\.id), [
        "f1s-401839133-\(Int(utc("2026-11-20T00:30Z").timeIntervalSince1970))",
        "f1s-401839136-\(Int(utc("2026-11-21T04:00Z").timeIntervalSince1970))",
        "f1-401839137-\(Int(utc("2026-11-22T04:00Z").timeIntervalSince1970))"])
    conferir("F1: nome das sessões, a corrida sem", corridas.map { $0.sessao ?? "corrida" }, ["Treino 1", "Classificação", "corrida"])
    conferir("F1: título da ESPN", corridas.last?.titulo, "Heineken Las Vegas GP")
    conferir("F1: largada", corridas.last?.inicio, utc("2026-11-22T04:00Z"))
    conferir("F1: o placar ao vivo só vê a corrida", corridas.compactMap(Placar.idESPN), ["401839137"])
    conferir("F1: sessão não lembra, a corrida sim",
             EventoInteresse.lembretes(corridas, agora: utc("2026-11-19T23:45Z"), disparados: []).map(\.evento.sessao),
             [nil as String?])
    // IndyCar como a ESPN manda (forma vista em 18/11/2026): uma competição, sem `type`. A terminada sai.
    let indy = """
        {"events":[{"id":"202609061784","name":"Grand Prix of Monterey","shortName":"Monterey","competitions":[
        {"id":"202609061784","date":"2026-09-06T18:30Z","status":{"type":{"completed":true}}}]},
        {"id":"202703011700","name":"Grand Prix of St. Petersburg","shortName":"St. Petersburg","competitions":[
        {"id":"202703011700","date":"2027-03-01T17:00Z","status":{"type":{"completed":false}}}]}]}
        """
    let indyCar = ESPN.corridas(de: Data(indy.utf8), fonte: .categoria(.indycar)) ?? []
    conferir("IndyCar: sem sigla é corrida, a terminada sai", indyCar.map(\.id),
             ["corrida-202703011700-\(Int(utc("2027-03-01T17:00Z").timeIntervalSince1970))"])
    conferir("IndyCar: placar ao vivo pela ESPN", indyCar.compactMap(Placar.idESPN), ["202703011700"])
    conferir("IndyCar lembra", indyCar.first.map { $0.sessao == nil && $0.fonte.corrida }, true)
    conferir("sigla nova de sessão aparece como veio", ESPN.nomeDaSessao("SQ"), "SQ")
    conferir("sigla vazia: a sessão sai", ESPN.nomeDaSessao(""), nil as String?)

    // Lista real de times do Brasileirão e da NFL, cortada.
    let timesReais = """
        {"sports":[{"leagues":[{"teams":[
        {"team":{"id":"3458","abbreviation":"CAP","displayName":"Athletico-PR","shortDisplayName":"Athletico-PR"}},
        {"team":{"id":"7632","abbreviation":"CAM","displayName":"Atlético-MG","shortDisplayName":"Atlético-MG"}},
        {"team":{"id":"9967","abbreviation":"BAH","displayName":"Bahia","shortDisplayName":"Bahia"}}]}]}]}
        """
    let brasileirao = Liga.todas[3]
    conferir("busca sem acento acha com acento", ESPN.times(de: Data(timesReais.utf8), liga: brasileirao, busca: "atletico"),
             [.espnTime(esporte: "soccer", liga: "bra.1", time: "7632", nome: "Atlético-MG")])
    conferir("busca pela abreviação", ESPN.times(de: Data(timesReais.utf8), liga: brasileirao, busca: "bah").map(\.nome), ["Bahia"])
    conferir("busca vazia: nada", ESPN.times(de: Data(timesReais.utf8), liga: brasileirao, busca: "  "), [])
    conferir("id estranho é descartado", ESPN.times(de: Data(
        #"{"sports":[{"leagues":[{"teams":[{"team":{"id":"2/../x","displayName":"Bills"}}]}]}]}"#.utf8), liga: Liga.todas[0], busca: "bills"), [])

    conferir("URL da agenda", ESPN.urlAgenda(esporte: "football", liga: "nfl", time: "2")?.absoluteString,
             "https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/2/schedule?fixture=true")
    conferir("URL dos times", ESPN.urlTimes(brasileirao)?.absoluteString,
             "https://site.api.espn.com/apis/site/v2/sports/soccer/bra.1/teams")

    // MARK: Seguidos

    conferir("Bills é válido", Seguido.bills.valido, true)
    conferir("liga desconhecida", Seguido.espnTime(esporte: "football", liga: "xfl", time: "2", nome: "X").valido, false)
    conferir("time com barra", Seguido.espnTime(esporte: "football", liga: "nfl", time: "2/x", nome: "X").valido, false)
    conferir("webcal vira https", Seguido.calendario(" webcal://exemplo.com/jogos.ics "),
             .ics(url: URL(string: "https://exemplo.com/jogos.ics")!))
    conferir("http não", Seguido.calendario("http://exemplo.com/a.ics"), nil)
    conferir("sem host não", Seguido.calendario("https:///a.ics"), nil)
    conferir("ftp não", Seguido.calendario("ftp://exemplo.com/a.ics"), nil)
    conferir("usuário no endereço não", Seguido.calendario("https://exemplo.com@evil.example/a.ics"), nil)
    conferir("ICS colado é válido", Seguido.calendario("https://exemplo.com/a.ics")?.valido, true)

    conferir("nome do calendário", ICS.nome(de: "BEGIN:VCALENDAR\r\nX-WR-CALNAME:Porsche Cup\\, 2027\r\nBEGIN:VEVENT\r\nEND:VEVENT\r\nEND:VCALENDAR"),
             "Porsche Cup, 2027")
    conferir("nome do calendário: só no cabeçalho", ICS.nome(de: "BEGIN:VCALENDAR\nBEGIN:VEVENT\nX-WR-CALNAME:Evento\nEND:VEVENT"), nil)
    conferir("nome do calendário: vazio não vale", ICS.nome(de: "BEGIN:VCALENDAR\nX-WR-CALNAME:   \nEND:VCALENDAR"), nil)

    // MARK: Categorias (F2, WEC, IMSA)

    let salvas = try? JSONEncoder().encode([Seguido.f1, .categoria(.wec)])
    conferir("categoria sobrevive ao salvar", salvas.flatMap { try? JSONDecoder().decode([Seguido].self, from: $0) },
             [.f1, .categoria(.wec)])
    conferir("categorias: ICS em https ou liga da ESPN, nunca os dois",
             Categoria.allCases.allSatisfy { c in
                 c.ics.map { $0.scheme == "https" && $0.host() != nil && c.ligaESPN == nil } ?? (c.ligaESPN != nil)
             }, true)
    conferir("sessões pelo título", ["F2: Practice (Qatar)", "F2: Qualifying (Qatar)", "F2: Sprint (Qatar)",
                                      "F2: Feature (Qatar)", "WTSC Race", "FIA WEC | [TEST] Prologue",
                                      "Roar Before The Rolex 24", "FIA WEC | 6 Hours of Imola", "ILMC qual : 24 Heures du Mans",
                                      "LM: Qualifying Practice", "WEC - Le Mans Test Day", "Protest Cup"].map(Categoria.sessao),
             ["Treino", "Classificação", nil, nil, nil, "Teste", "Teste", nil, "Classificação", "Classificação", "Teste", nil])
    let comCategoriaNova = Data(#"[{"f1":{}},{"categoria":{"_0":"motogp"}},{"espnTime":{"esporte":"football","liga":"nfl","time":"2","nome":"Buffalo Bills"}}]"#.utf8)
    conferir("item que não decodifica cai sozinho", Interesses.lerSeguidos(comCategoriaNova), [.f1, .bills])
    conferir("categoria sem placar da ESPN",
             Placar.idESPN(EventoInteresse(id: "ics-1795000000-abc", titulo: "WTSC Race", inicio: .now,
                                           fonte: .categoria(.imsa))), nil)

    // MARK: ICS

    let fonte = Seguido.calendario("https://exemplo.com/a.ics")!
    let ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
        + "BEGIN:VEVENT\r\nUID:jogo-1@exemplo.com\r\nDTSTART:20261122T180000Z\r\nSUMMARY:Flamengo x Palmeiras\\, final\r\nEND:VEVENT\r\n"
        + "BEGIN:VEVENT\r\nUID:jogo-2\r\nDTSTART;TZID=America/New_York:20261122T130000\r\nSUMMARY:Um título\r\n  dobrado em duas linhas\r\nEND:VEVENT\r\n"
        + "BEGIN:VEVENT\r\nUID:feriado\r\nDTSTART;VALUE=DATE:20261122\r\nSUMMARY:Dia de jogo\r\nEND:VEVENT\r\n"
        + "BEGIN:VEVENT\r\nUID:aspas\r\nDTSTART;TZID=\"America/Sao_Paulo\":20261122T150000\r\nSUMMARY:Com aspas\r\nEND:VEVENT\r\n"
        + "BEGIN:VEVENT\r\nUID:sem-data\r\nSUMMARY:Sem DTSTART\r\nEND:VEVENT\r\n"
        + "BEGIN:VEVENT\r\nUID:sem-titulo\r\nDTSTART:20261122T180000Z\r\nEND:VEVENT\r\n"
        + "END:VCALENDAR\r\n"
    let lidos = ICS.eventos(de: ics, fonte: fonte, fusoLocal: cal.timeZone) ?? []
    conferir("ICS: os quatro com data e título", lidos.map(\.titulo),
             ["Flamengo x Palmeiras, final", "Um título dobrado em duas linhas", "Dia de jogo", "Com aspas"])
    conferir("ICS: UTC", lidos.first?.inicio, utc("2026-11-22T18:00Z"))
    conferir("ICS: TZID de Nova York (13:00 EST = 18:00Z)", lidos.dropFirst().first?.inicio, utc("2026-11-22T18:00Z"))
    conferir("ICS: dia inteiro à meia-noite local", lidos.dropFirst(2).first.map { [$0.diaInteiro ? 1 : 0, Int($0.inicio.timeIntervalSince1970)] },
             [1, Int(utc("2026-11-22T03:00Z").timeIntervalSince1970)])
    conferir("ICS: TZID entre aspas", lidos.last?.inicio, utc("2026-11-22T18:00Z"))
    conferir("ICS: id curto com a data", lidos.first?.id, "ics-1795370400-jogo1exemplocom")
    conferir("ICS: linhas só com \\n", ICS.eventos(de: ics.replacingOccurrences(of: "\r\n", with: "\n"), fonte: fonte,
                                                    fusoLocal: cal.timeZone)?.count, 4)
    conferir("ICS: lixo não quebra", ICS.eventos(de: "BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART:2026\nSUMMARY:x", fonte: fonte), [])
    conferir("ICS: página que não é calendário dá nil", ICS.eventos(de: "<html>login</html>", fonte: fonte), nil)
    conferir("ICS: cancelado fica de fora",
             ICS.eventos(de: "BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART:20261201T180000Z\nSUMMARY:Jogo\nSTATUS:CANCELLED\nEND:VEVENT", fonte: fonte), [])
    conferir("ICS: TZID desconhecido cai no fuso local",
             ICS.data("20261122T150000", parametros: ["TZID": "Eastern Standard Time"], fusoLocal: cal.timeZone)?.0,
             utc("2026-11-22T18:00Z"))

    // MARK: Lembretes

    // O lembrete de 1 hora de um jogo à 00:30 sai às 23:30 da véspera: "amanhã", não "hoje".
    let madrugada = EventoInteresse(id: "espn-2", titulo: "x", inicio: utc("2026-11-23T03:30Z"), fonte: .bills)  // 00:30 em SP
    conferir("1 hora antes, na véspera: amanhã",
             EventoInteresse.diaEHora(madrugada, agora: utc("2026-11-23T02:30Z"), calendario: cal).hasPrefix("amanhã"), true)
    conferir("1 hora antes, no mesmo dia: hoje",
             EventoInteresse.diaEHora(madrugada, agora: utc("2026-11-23T03:00Z"), calendario: cal).hasPrefix("hoje"), true)

    // Jogo no domingo 22/11, 15:00 em São Paulo (18:00Z). A semana dele começa na segunda 16/11, 09:00 (12:00Z).
    let jogo = EventoInteresse(id: "espn-1", titulo: "Bills x Dolphins", inicio: utc("2026-11-22T18:00Z"), fonte: .bills)
    func tipo(_ e: EventoInteresse, _ agora: String) -> TipoLembrete? { EventoInteresse.tipoDevido(e, agora: utc(agora), calendario: cal) }
    conferir("segunda 09:00 da semana do jogo", EventoInteresse.segunda9h(da: jogo.inicio, calendario: cal), utc("2026-11-16T12:00Z"))
    conferir("domingo anterior: nada", tipo(jogo, "2026-11-15T20:00Z"), nil)
    conferir("segunda 08:59: nada", tipo(jogo, "2026-11-16T11:59Z"), nil)
    conferir("segunda 09:00: o da semana", tipo(jogo, "2026-11-16T12:00Z"), .semana)
    conferir("sábado, 24 h e 1 min antes: ainda o da semana", tipo(jogo, "2026-11-21T17:59Z"), .semana)
    conferir("24 h antes: véspera", tipo(jogo, "2026-11-21T18:00Z"), .vespera)
    conferir("1 h e 1 min antes: véspera", tipo(jogo, "2026-11-22T16:59Z"), .vespera)
    conferir("1 h antes: o de 1 hora", tipo(jogo, "2026-11-22T17:00Z"), .umaHora)
    conferir("começou: nada", tipo(jogo, "2026-11-22T18:00Z"), nil)
    let segundaCedo = EventoInteresse(id: "x", titulo: "x", inicio: utc("2026-11-16T11:00Z"), fonte: .bills)  // segunda 08:00
    conferir("jogo segunda 08:00: sem o da semana, véspera no domingo", [tipo(segundaCedo, "2026-11-15T10:00Z"),
                                                                          tipo(segundaCedo, "2026-11-15T11:00Z")], [nil, .vespera])
    let diaInteiro = EventoInteresse(id: "d", titulo: "d", inicio: utc("2026-11-22T03:00Z"), diaInteiro: true, fonte: fonte)
    conferir("dia inteiro: véspera só às 09:00 do dia antes", [tipo(diaInteiro, "2026-11-21T11:59Z"),
                                                                tipo(diaInteiro, "2026-11-21T12:00Z"),
                                                                tipo(diaInteiro, "2026-11-22T02:30Z"),
                                                                tipo(diaInteiro, "2026-11-22T03:30Z")], [.semana, .vespera, .vespera, nil])

    // A semana inteira, minuto a minuto, guardando o que disparou: cada um uma vez, na ordem, e nada depois do início.
    func simular(de inicio: String, ate fim: String, dormindo: ClosedRange<Date>? = nil) -> [TipoLembrete] {
        var disparados: Set<String> = []
        var vistos: [TipoLembrete] = []
        var agora = utc(inicio)
        while agora <= utc(fim) {
            if dormindo?.contains(agora) != true {
                for l in EventoInteresse.lembretes([jogo], agora: agora, disparados: disparados, calendario: cal) {
                    disparados.insert(l.chave)
                    vistos.append(l.tipo)
                }
            }
            agora.addTimeInterval(60)
        }
        return vistos
    }
    conferir("semana toda: cada um uma vez", simular(de: "2026-11-15T00:00Z", ate: "2026-11-23T00:00Z"), [.semana, .vespera, .umaHora])
    conferir("adicionado na quarta: o da semana na hora", simular(de: "2026-11-18T15:00Z", ate: "2026-11-18T15:00Z"), [.semana])
    conferir("Mac dormindo de sexta até 30 min antes: só o de 1 hora",
             simular(de: "2026-11-20T00:00Z", ate: "2026-11-23T00:00Z",
                     dormindo: utc("2026-11-20T00:00Z")...utc("2026-11-22T17:29Z")), [.umaHora])
    conferir("acordou depois do início: nada",
             simular(de: "2026-11-20T00:00Z", ate: "2026-11-23T00:00Z",
                     dormindo: utc("2026-11-20T00:00Z")...utc("2026-11-22T18:05Z")), [])
    let chaves = EventoInteresse.lembretes([jogo], agora: utc("2026-11-21T20:00Z"), disparados: [], calendario: cal).map(\.chave)
    conferir("chave do lembrete", chaves, ["espn-1-vespera"])
    conferir("chave guardada (reinício) não repete",
             EventoInteresse.lembretes([jogo], agora: utc("2026-11-21T20:01Z"), disparados: Set(chaves), calendario: cal), [])
    conferir("poda o que começou há mais de 2 dias",
             EventoInteresse.podar(["velho-umaHora": utc("2026-11-13T18:00Z"), "novo-semana": utc("2026-11-22T18:00Z")],
                                   agora: utc("2026-11-16T12:00Z")).keys.sorted(), ["novo-semana"])

    // MARK: Próximo e "quando"

    let longe = EventoInteresse(id: "l", titulo: "l", inicio: utc("2026-12-06T21:25Z"), fonte: .bills)
    conferir("próximo: o de dentro de 7 dias", EventoInteresse.proximo([longe, jogo], agora: utc("2026-11-16T12:00Z"))?.id, "espn-1")
    conferir("próximo: a 20 dias ainda entra na box", EventoInteresse.proximo([longe], agora: utc("2026-11-16T12:00Z"))?.id, "l")
    conferir("próximo: mais de 30 dias fica fora", EventoInteresse.proximo([longe], agora: utc("2026-11-05T12:00Z")), nil)
    conferir("próximo: o que começou não conta", EventoInteresse.proximo([jogo], agora: utc("2026-11-22T18:01Z")), nil)
    let corrida = EventoInteresse(id: "f1-1", titulo: "Las Vegas", inicio: utc("2026-11-22T04:00Z"), fonte: .f1)
    let outroJogo = EventoInteresse(id: "espn-2", titulo: "Bills @ Jets", inicio: utc("2026-11-29T18:00Z"), fonte: .bills)
    conferir("lado a lado: o próximo de cada fonte, o mais perto primeiro",
             EventoInteresse.proximos([outroJogo, jogo, corrida], agora: utc("2026-11-16T12:00Z")).map(\.id), ["f1-1", "espn-1"])
    func quando(_ agora: String, _ e: EventoInteresse = jogo) -> String { EventoInteresse.quando(e, agora: utc(agora), calendario: cal) }
    conferir("quando: em 45 min", quando("2026-11-22T17:15Z"), "em 45 min")
    conferir("quando: em 1 hora", quando("2026-11-22T17:00Z"), "em 1 hora")
    conferir("quando: hoje", quando("2026-11-22T12:00Z"), "hoje 15:00")
    conferir("quando: amanhã", quando("2026-11-21T20:00Z"), "amanhã 15:00")
    conferir("quando: dia da semana", quando("2026-11-16T12:00Z"), "dom. 15:00")
    conferir("quando: mais de 7 dias, dia e mês", quando("2026-11-10T12:00Z"), "22 de nov. 15:00")
    conferir("quando: começou", quando("2026-11-22T18:00Z"), "agora")
    conferir("quando: dia inteiro amanhã", quando("2026-11-21T12:00Z", diaInteiro), "amanhã")

    // MARK: Rede

    let resposta = { (url: String, status: Int, tamanho: Int?) in
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil,
                        headerFields: tamanho.map { ["Content-Length": "\($0)"] })!
    }
    let espn = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/2/schedule"
    conferir("resposta boa", RedeInteresses.aceitar(resposta(espn, 200, 300_000), host: ESPN.host, teto: ESPN.tamanhoMaximo), true)
    conferir("status 404", RedeInteresses.aceitar(resposta(espn, 404, nil), host: ESPN.host, teto: ESPN.tamanhoMaximo), false)
    conferir("redirecionada para outro host",
             RedeInteresses.aceitar(resposta("https://site.api.espn.com.evil.example/x", 200, nil), host: ESPN.host, teto: 10), false)
    conferir("HTTP sem S", RedeInteresses.aceitar(resposta("http://site.api.espn.com/x", 200, nil), host: ESPN.host, teto: 10), false)
    conferir("Content-Length acima do teto",
             RedeInteresses.aceitar(resposta(espn, 200, 3_000_000), host: ESPN.host, teto: ESPN.tamanhoMaximo), false)
    conferir("ICS no host que a pessoa colou",
             RedeInteresses.aceitar(resposta("https://exemplo.com/a.ics", 200, 500), host: "exemplo.com", teto: ICS.tamanhoMaximo), true)
}
