import Foundation

/// O placar de um jogo seguido enquanto ele acontece, lido do scoreboard da ESPN. Times, placar e situação são
/// conteúdo: nunca vão para o log.
// ponytail: só times da ESPN (`.espnTime`). O scoreboard da F1 não tem placar, só a ordem de chegada; ler a
// classificação de `competitors[].order` se a pessoa quiser a corrida ao vivo.
struct Placar: Equatable, Sendable {
    let eventoId: String
    /// Abreviações da ESPN ("BUF", "KC"): ASCII, até 6 letras ou dígitos.
    let casa: String
    let visitante: String
    let pontosCasa: Int
    let pontosVisitante: Int
    /// O `shortDetail` da ESPN ("9:12 - 3rd", "Halftime", "Final"), em inglês: dado, mostrado com `Text(verbatim:)`.
    let situacao: String
    let encerrado: Bool
    let link: URL?

    /// Para a asa da ilha fechada: "LAC 20–13 BAL", visitante primeiro, como a ESPN escreve "LAC @ BAL".
    var texto: String { "\(visitante) \(pontosVisitante)–\(pontosCasa) \(casa)" }

    /// Do início até 5 h depois: cobre prorrogação e atraso de chuva. Fora disso, nenhuma consulta.
    static let janela: TimeInterval = 5 * 3600

    static func deveConsultar(inicio: Date, agora: Date) -> Bool {
        agora >= inicio && agora.timeIntervalSince(inicio) <= janela
    }

    // MARK: Leitura

    private struct Resposta: Decodable { let events: [Evento]? }
    private struct Evento: Decodable {
        let id: String?
        let status: Status?
        let competitions: [Competicao]?
        let links: [ESPN.Link]?
    }
    private struct Status: Decodable {
        struct Tipo: Decodable {
            let state: String?
            let completed: Bool?
            let shortDetail: String?
        }
        let type: Tipo?
    }
    private struct Competicao: Decodable {
        let status: Status?
        let competitors: [Lado]?
    }
    /// No scoreboard o `score` é texto ("13"); na agenda do time é um objeto, mas a agenda não passa por aqui.
    private struct Lado: Decodable {
        let homeAway: String?
        let score: String?
        let team: ESPN.Time?
    }

    /// O placar do evento, ou nil quando ele não está na resposta, ainda não começou ("pre"), foi adiado
    /// ("post" sem `completed`) ou veio fora do formato.
    static func ler(_ dados: Data, eventoId: String) -> Placar? {
        guard let r = try? JSONDecoder().decode(Resposta.self, from: dados),
              let e = r.events?.first(where: { $0.id == eventoId }), let c = e.competitions?.first,
              let tipo = (e.status ?? c.status)?.type else { return nil }
        let encerrado: Bool
        switch (tipo.state, tipo.completed) {
        case ("in", _): encerrado = false
        case ("post", true): encerrado = true
        default: return nil
        }
        let lados = c.competitors ?? []
        guard lados.count == 2, let casa = lados.first(where: { $0.homeAway == "home" }),
              let fora = lados.first(where: { $0.homeAway == "away" }),
              let siglaCasa = sigla(casa.team?.abbreviation), let siglaFora = sigla(fora.team?.abbreviation),
              let pontosCasa = pontos(casa.score), let pontosFora = pontos(fora.score) else { return nil }
        return Placar(eventoId: eventoId, casa: siglaCasa, visitante: siglaFora, pontosCasa: pontosCasa,
                      pontosVisitante: pontosFora, situacao: Atividade.limpo(tipo.shortDetail ?? "", ate: 30),
                      encerrado: encerrado, link: ESPN.pagina(e.links))
    }

    /// Recusa em vez de cortar: uma abreviação estranha é sinal de resposta fora do formato.
    private static func sigla(_ texto: String?) -> String? {
        guard let texto, (1...6).contains(texto.count),
              texto.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return texto
    }

    private static func pontos(_ texto: String?) -> Int? {
        guard let texto, texto.count <= 3, let n = Int(texto), (0...999).contains(n) else { return nil }
        return n
    }

    // MARK: Eventos e rede

    /// O id da ESPN dentro do id do evento ("espn-401873065-1795…"). nil para F1, ICS ou id em outro formato.
    static func idESPN(_ e: EventoInteresse) -> String? {
        guard case .espnTime = e.fonte else { return nil }
        let partes = e.id.split(separator: "-")
        guard partes.count == 3, partes[0] == "espn", partes[1].allSatisfy(\.isNumber) else { return nil }
        return String(partes[1])
    }

    func eDo(_ e: EventoInteresse) -> Bool { Self.idESPN(e) == eventoId }

    /// Os jogos seguidos dentro da janela que ainda não terminaram, o que começou antes primeiro.
    static func emJogo(_ eventos: [EventoInteresse], agora: Date, encerrados: Set<String>) -> [EventoInteresse] {
        eventos
            .filter { e in idESPN(e).map { !encerrados.contains($0) } == true && deveConsultar(inicio: e.inicio, agora: agora) }
            .sorted { ($0.inicio, $0.id) < ($1.inicio, $1.id) }
            // Seguir os dois times do mesmo jogo dá o jogo duas vezes: uma consulta basta.
            .reduce(into: [EventoInteresse]()) { vistos, e in if !vistos.contains(where: { idESPN($0) == idESPN(e) }) { vistos.append(e) } }
    }

    /// A linha da ilha com o jogo ao vivo no lugar do próximo da mesma fonte: `proximos` só tem o que não começou.
    static func comAoVivo(_ proximos: [EventoInteresse], eventos: [EventoInteresse], aoVivo: Placar?,
                          maximo: Int = 3) -> [EventoInteresse] {
        guard let aoVivo, let jogo = eventos.first(where: aoVivo.eDo) else { return proximos }
        return Array(([jogo] + proximos.filter { $0.fonte != jogo.fonte && $0.id != jogo.id }).prefix(maximo))
    }

    /// `dates=` com o dia do início em Nova York: sem ele o scoreboard mostra "hoje" no horário da ESPN, e um jogo
    /// que passa da meia-noite de lá sumiria no meio. Com ele a resposta também encolhe (a NFL deixa de mandar a semana toda).
    static func url(esporte: String, liga: String, inicio: Date) -> URL? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let d = cal.dateComponents([.year, .month, .day], from: inicio)
        guard let ano = d.year, let mes = d.month, let dia = d.day else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = ESPN.host
        c.path = "/apis/site/v2/sports/\(esporte)/\(liga)/scoreboard"
        c.queryItems = [URLQueryItem(name: "dates", value: String(format: "%04d%02d%02d", ano, mes, dia))]
        return c.url
    }

    /// Um scoreboard por liga e dia, com a sessão e as regras de `RedeInteresses`. nil quando nenhum respondeu:
    /// aí o placar de antes continua valendo.
    static func buscar(_ jogos: [EventoInteresse]) async -> [Placar]? {
        var porURL: [URL: [EventoInteresse]] = [:]
        for jogo in jogos {
            guard jogo.fonte.valido, case let .espnTime(esporte, liga, _, _) = jogo.fonte,
                  let url = url(esporte: esporte, liga: liga, inicio: jogo.inicio) else { continue }
            porURL[url, default: []].append(jogo)
        }
        var placares: [Placar] = []
        var responderam = 0
        for (url, daqui) in porURL {
            guard url.host() == ESPN.host, let dados = await RedeInteresses.baixar(url, teto: ESPN.tamanhoMaximo) else { continue }
            responderam += 1
            placares += daqui.compactMap { idESPN($0).flatMap { ler(dados, eventoId: $0) } }
        }
        let ordem = jogos.compactMap(idESPN)
        return responderam == 0 && !porURL.isEmpty
            ? nil
            : placares.sorted { (ordem.firstIndex(of: $0.eventoId) ?? 0) < (ordem.firstIndex(of: $1.eventoId) ?? 0) }
    }
}
