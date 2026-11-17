import Foundation

/// O placar de um jogo ou a ponta de uma corrida de F1 seguidos enquanto acontecem, lidos do scoreboard da ESPN.
/// Times, pilotos, placar e situação são conteúdo: nunca vão para o log.
struct Placar: Equatable, Sendable {
    enum Lances: Equatable, Sendable {
        /// Abreviações da ESPN ("BUF", "KC"): ASCII, até 6 letras ou dígitos.
        case jogo(casa: String, visitante: String, pontosCasa: Int, pontosVisitante: Int)
        /// Os três primeiros da corrida, em siglas de três letras ("NOR", "VER", "HAD"); menos se a ESPN trouxer menos.
        case corrida([String])
    }

    /// O id do jogo ou, na F1, o da corrida (`competitions[].id`), que é o que `ESPN.corridas` põe no evento.
    let eventoId: String
    let lances: Lances
    /// O `shortDetail` da ESPN ("9:12 - 3rd", "Halftime", "Final"), em inglês: dado, mostrado com `Text(verbatim:)`.
    let situacao: String
    let encerrado: Bool
    let link: URL?

    /// "LAC 20–13 BAL", visitante primeiro, como a ESPN escreve "LAC @ BAL"; na corrida, "1 NOR · 2 VER · 3 HAD".
    var texto: String {
        switch lances {
        case let .jogo(casa, visitante, pontosCasa, pontosVisitante): "\(visitante) \(pontosVisitante)–\(pontosCasa) \(casa)"
        case .corrida(let siglas): siglas.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: " · ")
        }
    }

    /// Os dois lados da asa fechada, um de cada lado do notch: "LAC 20" e "13 BAL", ou "1 NOR" e "2 VER".
    var asa: (esquerda: String, direita: String) {
        switch lances {
        case let .jogo(casa, visitante, pontosCasa, pontosVisitante): ("\(visitante) \(pontosVisitante)", "\(pontosCasa) \(casa)")
        case .corrida(let siglas): (siglas.first.map { "1 \($0)" } ?? "", siglas.count > 1 ? "2 \(siglas[1])" : "")
        }
    }

    /// O detalhe da atividade que fica no mural quando acaba.
    var fim: String {
        switch lances {
        case .jogo: String(localized: "Fim de jogo")
        case .corrida: String(localized: "Fim da corrida")
        }
    }

    /// Até dois ao mesmo tempo: a linha da ilha mostra os dois, e a asa fechada só tem lugar para um.
    static let maximoAoVivo = 2
    /// Quanto cada um fica na asa quando há dois: dá para ler o placar, e a troca não vira pisca-pisca.
    static let vezNaAsa: TimeInterval = 8

    /// O da vez na asa fechada: com dois, um de cada vez, trocando a cada `vezNaAsa`. Conta só com o relógio
    /// (a `TimelineView` da asa), sem estado nem consulta a mais: o "que mudou por último" pediria guardar o
    /// placar anterior de cada jogo, e um jogo parado sumiria da asa.
    static func daVez(_ placares: [Placar], agora: Date) -> Placar? {
        guard !placares.isEmpty else { return nil }
        let vez = max(Int(agora.timeIntervalSinceReferenceDate / vezNaAsa), 0)
        return placares[vez % placares.count]
    }

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
        let id: String?
        let type: ESPN.Tipo?
        let status: Status?
        let competitors: [Lado]?
    }
    /// No scoreboard o `score` é texto ("13"); na agenda do time é um objeto, mas a agenda não passa por aqui.
    /// Na F1 cada lado é um piloto: `order` (a posição) e `athlete.shortName` ("L. Norris"), sem `team` nem `score`.
    private struct Lado: Decodable {
        struct Piloto: Decodable { let shortName: String? }
        let homeAway: String?
        let score: String?
        let team: ESPN.Time?
        let order: Int?
        let athlete: Piloto?
    }

    /// O placar do evento, ou nil quando ele não está na resposta, ainda não começou ("pre"), foi adiado
    /// ("post" sem `completed`) ou veio fora do formato.
    static func ler(_ dados: Data, eventoId: String) -> Placar? {
        guard let r = try? JSONDecoder().decode(Resposta.self, from: dados),
              let e = r.events?.first(where: { $0.id == eventoId }), let c = e.competitions?.first,
              let tipo = (e.status ?? c.status)?.type, let encerrado = encerrado(tipo) else { return nil }
        let lados = c.competitors ?? []
        guard lados.count == 2, let casa = lados.first(where: { $0.homeAway == "home" }),
              let fora = lados.first(where: { $0.homeAway == "away" }),
              let siglaCasa = sigla(casa.team?.abbreviation), let siglaFora = sigla(fora.team?.abbreviation),
              let pontosCasa = pontos(casa.score), let pontosFora = pontos(fora.score) else { return nil }
        return Placar(eventoId: eventoId,
                      lances: .jogo(casa: siglaCasa, visitante: siglaFora, pontosCasa: pontosCasa, pontosVisitante: pontosFora),
                      situacao: Atividade.limpo(tipo.shortDetail ?? "", ate: 30), encerrado: encerrado, link: ESPN.pagina(e.links))
    }

    /// A ponta da corrida: os três primeiros de `competitors[].order`, da sessão "Race" (o evento é o fim de semana
    /// todo, com treinos e classificação, e o status dele não diz se a corrida está rolando). Visto numa resposta
    /// real só com a corrida terminada (São Paulo, 08/11/2026): a lista vem em ordem de chegada, com `order` 1…22.
    // ponytail: a ordem durante a corrida não foi vista ao vivo; supõe que `order` anda com a classificação, como
    // no fim. Se vier parada na ordem de largada, ler a posição de outro campo da resposta ao vivo.
    static func lerCorrida(_ dados: Data, corridaId: String) -> Placar? {
        guard let r = try? JSONDecoder().decode(Resposta.self, from: dados) else { return nil }
        for e in r.events ?? [] {
            guard let c = e.competitions?.first(where: { $0.id == corridaId }) else { continue }
            guard c.type?.abbreviation == "Race", let tipo = c.status?.type, let encerrado = encerrado(tipo),
                  let siglas = ponta(c.competitors ?? []) else { return nil }
            return Placar(eventoId: corridaId, lances: .corrida(siglas), situacao: Atividade.limpo(tipo.shortDetail ?? "", ate: 30),
                          encerrado: encerrado, link: ESPN.pagina(e.links))
        }
        return nil
    }

    /// Em andamento (false), terminado (true) ou nil: não começou, ou adiado ("post" sem `completed`).
    private static func encerrado(_ tipo: Status.Tipo) -> Bool? {
        switch (tipo.state, tipo.completed) {
        case ("in", _): false
        case ("post", true): true
        default: nil
        }
    }

    /// As siglas das posições 1, 2 e 3, nessa ordem e sem buraco. nil se faltar a 1ª, se uma posição se repetir
    /// ou se um dos três tiver nome estranho: a ponta pela metade enganaria mais que nada.
    private static func ponta(_ pilotos: [Lado]) -> [String]? {
        let primeiros = pilotos.filter { ($0.order ?? 0) >= 1 && ($0.order ?? 0) <= 3 }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        guard !primeiros.isEmpty, primeiros.map(\.order) == (1...primeiros.count).map(Optional.some) else { return nil }
        let siglas = primeiros.compactMap { siglaPiloto($0.athlete?.shortName) }
        return siglas.count == primeiros.count ? siglas : nil
    }

    /// "L. Norris" → "NOR". O scoreboard não traz a sigla oficial (nem `abbreviation`), só nome; as três primeiras
    /// letras do sobrenome sem acento dão a sigla da TV para o grid de 2026 inteiro ("N. Hülkenberg" → "HUL",
    /// "S. Pérez" → "PER"). Recusa em vez de adivinhar: fora do formato "X. Sobrenome", com dígito, símbolo ou
    /// caractere de direção, ou sobrenome comprido demais, nil.
    static func siglaPiloto(_ nome: String?) -> String? {
        guard let nome, nome.count <= 30, let ponto = nome.firstIndex(of: "."),
              nome[..<ponto].count == 1, nome[nome.startIndex].isLetter else { return nil }
        let sobrenome = nome[nome.index(after: ponto)...].trimmingCharacters(in: .init(charactersIn: " "))
        guard (2...24).contains(sobrenome.count),
              sobrenome.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" || $0 == "'" }) else { return nil }
        let letras = sobrenome.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter(\.isLetter)
        let sigla = String(letras.prefix(3)).uppercased()
        return sigla.count == 3 && sigla.allSatisfy({ $0.isASCII && $0.isUppercase }) ? sigla : nil
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

    /// O id da ESPN dentro do id do evento ("espn-401873065-1795…", "f1-401839137-1795…"). nil para ICS ou id em
    /// outro formato.
    static func idESPN(_ e: EventoInteresse) -> String? {
        let prefixo: Substring
        switch e.fonte {
        case .espnTime: prefixo = "espn"
        case .f1: prefixo = "f1"
        case .ics: return nil
        }
        let partes = e.id.split(separator: "-")
        guard partes.count == 3, partes[0] == prefixo, partes[1].allSatisfy(\.isNumber) else { return nil }
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

    /// Os ao vivo, até `maximoAoVivo`, na ordem de `naJanela` (o que começou antes primeiro). O que não veio nesta
    /// consulta (a liga não respondeu, ou só é consultado de 5 em 5 min) fica com o placar de antes: uma falha de
    /// uma liga não apaga o jogo da outra. O encerrado sai.
    static func aoVivo(lidos: [Placar], antes: [Placar], naJanela: [EventoInteresse]) -> [Placar] {
        let placares = naJanela.compactMap(idESPN).compactMap { id -> Placar? in
            if let lido = lidos.first(where: { $0.eventoId == id }) { return lido.encerrado ? nil : lido }
            return antes.first { $0.eventoId == id }
        }
        return Array(placares.prefix(maximoAoVivo))
    }

    /// A linha da ilha com os ao vivo no lugar do próximo da mesma fonte: `proximos` só tem o que não começou.
    static func comAoVivo(_ proximos: [EventoInteresse], eventos: [EventoInteresse], aoVivo: [Placar],
                          maximo: Int = 3) -> [EventoInteresse] {
        let jogos = aoVivo.compactMap { p in eventos.first(where: p.eDo) }
        return Array((jogos + proximos.filter { e in !jogos.contains { $0.fonte == e.fonte || $0.id == e.id } }).prefix(maximo))
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
            // A F1 também aceita `dates=`: o dia da largada em Nova York traz o fim de semana dela (conferido com
            // Las Vegas, 22/11/2026 04:00Z → 20261121).
            let endereco: URL? = switch jogo.fonte {
            case let .espnTime(esporte, liga, _, _) where jogo.fonte.valido: url(esporte: esporte, liga: liga, inicio: jogo.inicio)
            case .f1: url(esporte: "racing", liga: "f1", inicio: jogo.inicio)
            default: nil
            }
            if let endereco { porURL[endereco, default: []].append(jogo) }
        }
        var placares: [Placar] = []
        var responderam = 0
        for (url, daqui) in porURL {
            guard url.host() == ESPN.host, let dados = await RedeInteresses.baixar(url, teto: ESPN.tamanhoMaximo) else { continue }
            responderam += 1
            placares += daqui.compactMap { e in
                idESPN(e).flatMap { e.fonte == .f1 ? lerCorrida(dados, corridaId: $0) : ler(dados, eventoId: $0) }
            }
        }
        return responderam == 0 && !porURL.isEmpty ? nil : placares
    }
}
