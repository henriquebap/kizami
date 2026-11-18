import AppKit
import Observation

/// Uma liga que a busca de times conhece. Os slugs foram conferidos na API da ESPN (16/11/2026).
struct Liga: Hashable, Identifiable, Sendable {
    let esporte: String
    let liga: String
    /// Nome próprio (NFL, Premier League): igual nas duas línguas, não passa pela tradução.
    let nome: String

    var id: String { "\(esporte)/\(liga)" }

    static let todas = [
        Liga(esporte: "football", liga: "nfl", nome: "NFL"),
        Liga(esporte: "basketball", liga: "nba", nome: "NBA"),
        Liga(esporte: "baseball", liga: "mlb", nome: "MLB"),
        Liga(esporte: "soccer", liga: "bra.1", nome: "Brasileirão"),
        Liga(esporte: "soccer", liga: "eng.1", nome: "Premier League"),
    ]
}

/// O que a pessoa segue, como fica guardado no `UserDefaults`. Só entra na lista depois de `valido`.
enum Seguido: Codable, Hashable, Sendable {
    /// `time` é o id numérico da ESPN: a abreviação funciona na NFL mas não no futebol (visto com "CAP" no Brasileirão).
    case espnTime(esporte: String, liga: String, time: String, nome: String)
    case f1
    case ics(url: URL)
    /// Categoria de corrida além da F1: pelo scoreboard da ESPN (IndyCar, NASCAR) ou por um calendário ICS de endereço
    /// fixo (F2, WEC, IMSA, que a ESPN não tem).
    case categoria(Categoria)

    static let bills = Seguido.espnTime(esporte: "football", liga: "nfl", time: "2", nome: "Buffalo Bills")

    var valido: Bool {
        switch self {
        case let .espnTime(esporte, liga, time, nome):
            Liga.todas.contains { $0.esporte == esporte && $0.liga == liga }
                && !time.isEmpty && time.count <= 10 && time.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
                && !nome.isEmpty && nome.count <= 60
        case .f1, .categoria: true
        case .ics(let url): Seguido.calendario(url.absoluteString) == self
        }
    }

    /// O endereço que a pessoa colou. `webcal://` é como os sites oferecem assinatura de calendário: vira https.
    /// Só https e com host; o endereço inteiro pode ter um token secreto (o do Google tem), então nunca vai para o log.
    static func calendario(_ texto: String) -> Seguido? {
        var texto = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard texto.count <= 2000 else { return nil }
        if texto.lowercased().hasPrefix("webcal://") { texto = "https://" + texto.dropFirst("webcal://".count) }
        guard let url = URL(string: texto), url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty, url.user == nil else { return nil }
        return .ics(url: url)
    }

    /// O que a ilha e os Ajustes mostram. Nome de time vem da ESPN: é dado, mostrado com `Text(verbatim:)`.
    var nome: String {
        switch self {
        case .espnTime(_, _, _, let nome): nome
        case .f1: String(localized: "Fórmula 1")
        case .ics(let url): url.host() ?? url.absoluteString
        case .categoria(let c): c.nome
        }
    }

    /// Corrida da ESPN (F1, IndyCar, NASCAR): o placar ao vivo é a ponta, não o placar de dois lados.
    var corrida: Bool {
        switch self {
        case .f1: true
        case .categoria(let c): c.ligaESPN != nil
        case .espnTime, .ics: false
        }
    }

    var simbolo: String {
        switch self {
        case .espnTime(let esporte, _, _, _):
            switch esporte {
            case "football": "football.fill"
            case "basketball": "basketball.fill"
            case "baseball": "baseball.fill"
            case "soccer": "soccerball"
            default: "sportscourt.fill"
            }
        case .f1, .categoria: "flag.checkered"
        case .ics: "calendar"
        }
    }

    /// Uma das `Atividade.cores`.
    var cor: String {
        switch self {
        case .espnTime: "azul"
        case .f1: "vermelho"
        case .ics: "roxo"
        case .categoria: "laranja"
        }
    }
}

/// Categorias de corrida além da F1. IndyCar e NASCAR vêm do scoreboard da ESPN, como a F1 (com placar ao vivo e
/// pódio); F2, WEC e IMSA a ESPN não tem (a API devolve 400) e vêm de um calendário público de endereço fixo.
/// Os endereços são uma decisão do ROADMAP (regra 8 do AGENTS): trocar ou somar um é decisão de novo.
enum Categoria: String, Codable, CaseIterable, Sendable {
    case indycar, nascar, f2, wec, imsa

    var nome: String {
        switch self {
        case .indycar: "IndyCar"
        case .nascar: "NASCAR Cup"
        case .f2: String(localized: "Fórmula 2")
        case .wec: "WEC"
        case .imsa: "IMSA"
        }
    }

    /// A liga no caminho da ESPN (`racing/<liga>/scoreboard`); nil nas que vêm de ICS.
    var ligaESPN: String? {
        switch self {
        case .indycar: "irl"
        case .nascar: "nascar-premier"
        case .f2, .wec, .imsa: nil
        }
    }

    /// F2: o do f1calendar.com (projeto aberto `sportstimes/f1`), com as quatro sessões. WEC e IMSA: calendários
    /// públicos do Google mantidos por fãs (o do WEC é da Radio Le Mans), os que o sync2cal.com indica.
    // ponytail: calendário de terceiro pode parar de ser atualizado; aí a página some da box e nada quebra.
    var ics: URL? {
        switch self {
        case .indycar, .nascar: nil
        case .f2: URL(string: "https://files-f2.motorsportcalendars.com/f2-calendar_p_q_sprint_feature.ics")!
        case .wec: URL(string: "https://calendar.google.com/calendar/ical/61jccgg4rshh1temqk0dj4lens%40group.calendar.google.com/public/basic.ics")!
        case .imsa: URL(string: "https://calendar.google.com/calendar/ical/b374eec704f6714ca47308cc76b0c599b75bdcd2df4693d5414b7a30baa3ad4e%40group.calendar.google.com/public/basic.ics")!
        }
    }

    /// Quanto o evento de dia inteiro do fim de semana cobre: "Motul Petit Le Mans" começa na quinta e a corrida é no sábado.
    static let fimDeSemana: TimeInterval = 4 * 24 * 3600

    /// As sessões de um calendário de categoria: pelo título (`sessao`) e, na IMSA, o evento de dia inteiro do fim de
    /// semana quando a corrida com hora está nele. Sem isso os dois lembravam. O WEC, só com dias inteiros, não muda.
    static func marcar(_ eventos: [EventoInteresse]) -> [EventoInteresse] {
        let porTitulo = eventos.map { e in
            var marcado = e
            marcado.sessao = sessao(e.titulo)
            return marcado
        }
        let corridasComHora = porTitulo.filter { !$0.diaInteiro && $0.sessao == nil }.map(\.inicio)
        return porTitulo.map { e in
            guard e.diaInteiro, e.sessao == nil,
                  corridasComHora.contains(where: { $0 >= e.inicio && $0.timeIntervalSince(e.inicio) < fimDeSemana }) else { return e }
            var marcado = e
            marcado.sessao = String(localized: "Fim de semana")
            return marcado
        }
    }

    /// Treino, classificação ou teste pelo título ("F2: Practice (Qatar)", "ILMC qual : 24 Heures du Mans",
    /// "[TEST] Prologue"): vira `sessao`, que aparece na box mas não lembra, como na F1. nil é corrida.
    /// Palavra inteira: "Contest" não é teste.
    // ponytail: palavras em inglês, as que os três calendários usam; um calendário em outra língua lembraria de tudo.
    static func sessao(_ titulo: String) -> String? {
        let palavras = Set(titulo.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if !palavras.isDisjoint(with: ["qualifying", "qualif", "qual", "hyperpole"]) { return String(localized: "Classificação") }
        if !palavras.isDisjoint(with: ["practice", "warmup", "warm"]) { return String(localized: "Treino") }
        if !palavras.isDisjoint(with: ["test", "prologue", "roar"]) { return String(localized: "Teste") }
        return nil
    }
}

/// Um jogo, corrida ou evento de um calendário seguido. O título é dado de fora: limpo como o de uma `Atividade`
/// e nunca registrado no log.
struct EventoInteresse: Equatable, Identifiable, Sendable {
    var id: String
    var titulo: String
    var inicio: Date
    var diaInteiro = false
    var fonte: Seguido
    /// A página do jogo ou da corrida na ESPN, aberta no clique. Só https em www.espn.com (`ESPN.pagina`).
    var link: URL? = nil
    /// Na F1, o treino, a classificação ou a sprint ("Treino 1"); nil na corrida e em tudo que não é F1.
    /// Sessão aparece na box, mas não lembra nem tem placar: cinco sessões por fim de semana encheriam a ilha de avisos.
    var sessao: String? = nil

    static let horizonte: TimeInterval = 7 * 24 * 3600
    /// A box mostra o próximo de cada fonte até 30 dias à frente: com 7, a F2 a 9 dias e o WEC fora de temporada
    /// deixavam a box vazia, e parecia que o app não tinha atualizado. Os lembretes não mudam.
    static let horizonteDaBox: TimeInterval = 30 * 24 * 3600

    /// Os da linha da ilha: o próximo de cada fonte seguida, lado a lado, o mais perto primeiro. Um só "próximo"
    /// escondia o jogo dos Bills atrás da corrida da F1 da véspera (pedido da pessoa: ver os dois).
    static func proximos(_ eventos: [EventoInteresse], agora: Date, maximo: Int = 5) -> [EventoInteresse] {
        let porFonte = Dictionary(grouping: eventos, by: \.fonte).compactMap { proximo($0.value, agora: agora) }
        return Array(porFonte.sorted { ($0.inicio, $0.titulo) < ($1.inicio, $1.titulo) }.prefix(maximo))
    }

    static func proximo(_ eventos: [EventoInteresse], agora: Date) -> EventoInteresse? {
        eventos
            .filter { $0.inicio > agora && $0.inicio.timeIntervalSince(agora) <= horizonteDaBox }
            .min { ($0.inicio, $0.titulo) < ($1.inicio, $1.titulo) }  // título desempata: a escolha não pisca
    }

    /// "hoje 20:15" ou "amanhã 00:30", sem contagem: o texto do lembrete de 1 hora, que fica parado na ilha.
    static func diaEHora(_ e: EventoInteresse, agora: Date, calendario: Calendar = .current) -> String {
        let hora = e.inicio.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: calendario.locale ?? .current,
                                                       calendar: calendario, timeZone: calendario.timeZone))
        return calendario.isDate(e.inicio, inSameDayAs: agora) ? String(localized: "hoje \(hora)")
            : String(localized: "amanhã \(hora)")
    }

    /// "em 45 min", "hoje 20:15", "amanhã 14:00", "dom. 14:00", "27 de nov. 06:00". O dia da semana só na semana:
    /// depois "sex." seria esta ou a outra sexta. Contagem na última hora, quando "quanto falta"
    /// importa mais que "a que horas".
    static func quando(_ e: EventoInteresse, agora: Date, calendario: Calendar = .current) -> String {
        let falta = e.inicio.timeIntervalSince(agora)
        if falta <= 0 { return String(localized: "agora") }
        if !e.diaInteiro && falta <= 3600 {
            let minutos = Int((falta / 60).rounded(.up))
            return minutos >= 60 ? String(localized: "em 1 hora") : String(localized: "em \(minutos) min")
        }
        let locale = calendario.locale ?? .current
        let hora = e.diaInteiro ? nil : e.inicio.formatted(Date.FormatStyle(
            date: .omitted, time: .shortened, locale: locale, calendar: calendario, timeZone: calendario.timeZone))
        if calendario.isDate(e.inicio, inSameDayAs: agora), let hora { return String(localized: "hoje \(hora)") }
        if let amanha = calendario.date(byAdding: .day, value: 1, to: agora), calendario.isDate(e.inicio, inSameDayAs: amanha) {
            return hora.map { String(localized: "amanhã \($0)") } ?? String(localized: "amanhã")
        }
        let formato = Date.FormatStyle(locale: locale, calendar: calendario, timeZone: calendario.timeZone)
        let dia = falta < horizonte ? e.inicio.formatted(formato.weekday(.abbreviated))
            : e.inicio.formatted(formato.day().month(.abbreviated))
        return [dia, hora].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: Lembretes

enum TipoLembrete: String, Sendable {
    case semana, vespera, umaHora
}

struct LembreteInteresse: Equatable, Sendable {
    let evento: EventoInteresse
    let tipo: TipoLembrete
    /// O que já foi avisado, guardado no `UserDefaults`: um de cada tipo por evento, também depois de reiniciar.
    var chave: String { "\(evento.id)-\(tipo.rawValue)" }
}

extension EventoInteresse {
    /// Os avisos devidos agora. As janelas se encostam e só a da hora atual vale: o da semana vai da segunda 09:00
    /// até a véspera, o da véspera até 1 hora antes, o de 1 hora até o início. Mac dormindo na hora de um aviso
    /// ganha o da janela em que acordou, nunca um atrasado; evento que entra no meio da semana ganha o da semana na hora.
    static func lembretes(_ eventos: [EventoInteresse], agora: Date, disparados: Set<String>,
                          calendario: Calendar = .current) -> [LembreteInteresse] {
        eventos.compactMap { e in
            guard e.sessao == nil, let tipo = tipoDevido(e, agora: agora, calendario: calendario) else { return nil }
            let lembrete = LembreteInteresse(evento: e, tipo: tipo)
            return disparados.contains(lembrete.chave) ? nil : lembrete
        }
    }

    static func tipoDevido(_ e: EventoInteresse, agora: Date, calendario: Calendar) -> TipoLembrete? {
        // Dia inteiro não tem "1 hora antes", e a véspera começa às 09:00 do dia anterior, não à meia-noite.
        let umaHora = e.diaInteiro ? e.inicio : e.inicio.addingTimeInterval(-3600)
        let vespera = e.inicio.addingTimeInterval(e.diaInteiro ? -15 * 3600 : -24 * 3600)
        if agora >= e.inicio { return nil }
        if agora >= umaHora { return .umaHora }
        if agora >= vespera { return .vespera }
        if agora >= segunda9h(da: e.inicio, calendario: calendario) { return .semana }
        return nil
    }

    /// Segunda-feira 09:00 da semana do evento, no fuso do Mac. Jogo na segunda de manhã fica sem o da semana:
    /// a véspera já cobre.
    static func segunda9h(da data: Date, calendario: Calendar) -> Date {
        var cal = calendario
        cal.firstWeekday = 2
        guard let inicioSemana = cal.dateInterval(of: .weekOfYear, for: data)?.start,
              let nove = cal.date(bySettingHour: 9, minute: 0, second: 0, of: inicioSemana) else {
            return data.addingTimeInterval(-horizonte)
        }
        return nove
    }

    /// Esquece o aviso de evento que começou há mais de 2 dias: não volta a ser devido, e a lista não cresce sem fim.
    static func podar(_ disparados: [String: Date], agora: Date) -> [String: Date] {
        disparados.filter { $0.value > agora.addingTimeInterval(-2 * 24 * 3600) }
    }
}

// MARK: ESPN

/// A API pública da ESPN, sem chave. Não é documentada e pode mudar: tudo que depende da forma dela fica aqui.
enum ESPN {
    static let host = "site.api.espn.com"
    /// A agenda de um time da NBA tem ~900 KB (82 jogos com logos); a da NFL, ~300 KB.
    static let tamanhoMaximo = 2_000_000

    struct RespostaAgenda: Decodable {
        let events: [Evento]?
    }
    // Quase tudo opcional: um jogo com vaga ainda indefinida (time sem id) derrubava a agenda inteira na decodificação.
    struct Evento: Decodable {
        let id: String?
        let date: String?
        let name: String?
        let shortName: String?
        /// Falso quando a hora ainda não saiu ("TBD"): a data vem com uma hora de enfeite (visto: 05:00Z na semana 18).
        let timeValid: Bool?
        let competitions: [Competicao]?
        let links: [Link]?
    }
    struct Link: Decodable { let href: String? }

    /// A primeira página do evento no site da ESPN. Os outros links da resposta (app, apostas) ficam de fora.
    static func pagina(_ links: [Link]?) -> URL? {
        (links ?? []).lazy.compactMap { $0.href.flatMap(URL.init(string:)) }
            .first { $0.scheme == "https" && $0.host() == "www.espn.com" }
    }
    struct Competicao: Decodable {
        let id: String?
        let date: String?
        let type: Tipo?
        let competitors: [Competidor]?
        let status: Status?
    }
    struct Tipo: Decodable { let abbreviation: String? }
    struct Status: Decodable {
        struct Estado: Decodable { let completed: Bool? }
        let type: Estado?
    }
    struct Competidor: Decodable {
        let homeAway: String?
        let team: Time?
    }
    struct Time: Decodable {
        let id: String?
        let displayName: String?
        let shortDisplayName: String?
        let abbreviation: String?
    }
    struct RespostaTimes: Decodable {
        struct Esporte: Decodable { let leagues: [LigaTimes] }
        struct LigaTimes: Decodable { let teams: [Item] }
        struct Item: Decodable { let team: Time }
        let sports: [Esporte]
    }

    private static func url(_ caminho: String, consulta: [URLQueryItem] = []) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/apis/site/v2/sports/" + caminho
        c.queryItems = consulta.isEmpty ? nil : consulta
        return c.url
    }

    /// `fixture=true`: sem ele o futebol só devolve os jogos que já foram (visto no Brasileirão); a NFL e a NBA
    /// devolvem a mesma coisa com ou sem.
    static func urlAgenda(esporte: String, liga: String, time: String) -> URL? {
        url("\(esporte)/\(liga)/teams/\(time)/schedule", consulta: [URLQueryItem(name: "fixture", value: "true")])
    }
    static func urlTimes(_ liga: Liga) -> URL? { url("\(liga.esporte)/\(liga.liga)/teams") }
    static let urlF1 = url("racing/f1/scoreboard")
    static func urlCorridas(liga: String) -> URL? { url("racing/\(liga)/scoreboard") }

    /// "2026-11-22T18:00Z": sem segundos, que o ISO 8601 da Foundation exige.
    static func data(_ texto: String) -> Date? {
        let completo = texto.count == 17 && texto.hasSuffix("Z") ? texto.dropLast() + ":00Z" : Substring(texto)
        return try? Date(String(completo), strategy: .iso8601)
    }

    /// Os jogos ainda não terminados do time, do ponto de vista dele: "Bills x Dolphins" em casa, "Bills @ Jets" fora.
    /// nil quando a resposta não é uma agenda (erro com status 200): aí a lista de antes continua valendo.
    /// O início entra no id: um jogo que muda de horário (o "flex" da NFL) ganha lembretes novos.
    static func jogos(de dados: Data, time: String, fonte: Seguido) -> [EventoInteresse]? {
        guard let r = try? JSONDecoder().decode(RespostaAgenda.self, from: dados), let eventos = r.events else { return nil }
        return eventos.compactMap { e in
            guard e.timeValid != false, let id = e.id, let inicio = e.date.flatMap(data), let c = e.competitions?.first,
                  c.status?.type?.completed != true, let lados = c.competitors?.compactMap(\.self), lados.count == 2,
                  let nosso = lados.first(where: { $0.team?.id == time }), let nossoTime = nosso.team,
                  let outroTime = lados.first(where: { $0.team?.id != time })?.team else { return nil }
            let nome = { (t: Time) in t.shortDisplayName ?? t.displayName ?? t.abbreviation ?? "?" }
            let titulo = Atividade.limpo("\(nome(nossoTime)) \(nosso.homeAway == "away" ? "@" : "x") \(nome(outroTime))", ate: 60)
            return EventoInteresse(id: "espn-\(Atividade.limpo(id, ate: 20))-\(Int(inicio.timeIntervalSince1970))",
                                   titulo: titulo, inicio: inicio, fonte: fonte, link: pagina(e.links))
        }
    }

    /// O placar da F1 só traz o fim de semana atual (ou o próximo): treinos, classificação, sprint e corrida, todos.
    /// A corrida fica com o id `f1-…` (o do placar ao vivo); as outras sessões, `f1s-…`, que o `Placar` não consulta.
    // ponytail: só o fim de semana que o placar mostra; o `calendar` da resposta tem o ano todo, mas só com
    // o intervalo do fim de semana, sem a hora da largada. Ler o evento de cada etapa se a pessoa quiser a de daqui a duas semanas.
    /// F1, IndyCar ou NASCAR. A F1 lista cada sessão com sigla ("FP1", "Race"); IndyCar e NASCAR trazem só a corrida,
    /// sem `type`: sem sigla é corrida. Id "f1-…" na F1 e "corrida-…" nas outras (`Placar.idESPN` lê o prefixo).
    static func corridas(de dados: Data, fonte: Seguido = .f1) -> [EventoInteresse]? {
        guard let r = try? JSONDecoder().decode(RespostaAgenda.self, from: dados), let eventos = r.events else { return nil }
        let prefixo = fonte == .f1 ? "f1" : "corrida"
        return eventos.flatMap { e in
            (e.competitions ?? []).compactMap { c -> EventoInteresse? in
                let sigla = c.type?.abbreviation ?? "Race"
                guard c.status?.type?.completed != true, let id = c.id, let inicio = c.date.flatMap(data) else { return nil }
                let titulo = Atividade.limpo(e.shortName ?? e.name ?? "", ate: 60)
                let sessao = sigla == "Race" ? nil : nomeDaSessao(sigla)
                guard !titulo.isEmpty, sigla == "Race" || sessao != nil else { return nil }
                return EventoInteresse(id: "\(prefixo)\(sessao == nil ? "" : "s")-\(Atividade.limpo(id, ate: 20))-\(Int(inicio.timeIntervalSince1970))",
                                       titulo: titulo, inicio: inicio, fonte: fonte, link: pagina(e.links), sessao: sessao)
            }
        }
    }

    /// "FP1" → "Treino 1". Sigla que não está aqui (a ESPN muda o formato da sprint de um ano para o outro) aparece
    /// como veio, limpa; vazia, a sessão sai.
    static func nomeDaSessao(_ sigla: String) -> String? {
        switch sigla {
        case "FP1": String(localized: "Treino 1")
        case "FP2": String(localized: "Treino 2")
        case "FP3": String(localized: "Treino 3")
        case "Qual": String(localized: "Classificação")
        case "Sprint": String(localized: "Sprint")
        default: { let limpa = Atividade.limpo(sigla, ate: 20); return limpa.isEmpty ? nil : limpa }()
        }
    }

    /// Os times da liga cujo nome ou abreviação contém a busca, sem ligar para acento nem maiúscula. No máximo 10.
    static func times(de dados: Data, liga: Liga, busca: String) -> [Seguido] {
        let busca = busca.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busca.isEmpty, let r = try? JSONDecoder().decode(RespostaTimes.self, from: dados) else { return [] }
        let times = r.sports.flatMap(\.leagues).flatMap(\.teams).map(\.team)
        return times
            .filter { t in [t.displayName, t.shortDisplayName, t.abbreviation].contains { $0?.localizedStandardContains(busca) == true } }
            .compactMap { t in
                guard let id = t.id else { return nil }
                let s = Seguido.espnTime(esporte: liga.esporte, liga: liga.liga, time: id,
                                         nome: Atividade.limpo(t.displayName ?? t.shortDisplayName ?? "", ate: 60))
                return s.valido ? s : nil
            }
            .sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }
            .prefix(10)
            .map { $0 }
    }
}

// MARK: ICS

/// Um leitor mínimo de `VEVENT`: `DTSTART`, `SUMMARY` e `UID`. Sem dependência.
// ponytail: sem RRULE: um evento recorrente aparece só na primeira data. Feeds de jogos listam cada jogo como um
// VEVENT; expandir a regra se alguém seguir um calendário de reuniões semanais.
enum ICS {
    static let tamanhoMaximo = 1_000_000

    /// nil quando o texto não é um calendário (uma página de login, um erro): aí a lista de antes continua valendo.
    static func eventos(de texto: String, fonte: Seguido, fusoLocal: TimeZone = .current) -> [EventoInteresse]? {
        guard texto.range(of: "BEGIN:VCALENDAR", options: .caseInsensitive) != nil else { return nil }
        // Dobra de linha (RFC 5545 3.1): uma linha que começa com espaço ou tab continua a anterior.
        let linhas = texto.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
            .split(separator: "\n", omittingEmptySubsequences: true)
        var eventos: [EventoInteresse] = []
        var campos: [String: (parametros: [String: String], valor: String)]?
        for linha in linhas {
            let (nome, parametros, valor) = propriedade(String(linha))
            if nome == "BEGIN" && valor.uppercased() == "VEVENT" { campos = [:]; continue }
            if nome == "END" && valor.uppercased() == "VEVENT" {
                if let c = campos, let e = evento(c, fonte: fonte, fusoLocal: fusoLocal) { eventos.append(e) }
                campos = nil
                continue
            }
            if campos != nil, campos?[nome] == nil { campos?[nome] = (parametros, valor) }
        }
        return eventos
    }

    /// "DTSTART;TZID=America/New_York:20261122T130000" → nome, parâmetros e valor. O valor começa no primeiro
    /// ":" fora de aspas: parâmetro entre aspas pode ter ":".
    static func propriedade(_ linha: String) -> (String, [String: String], String) {
        var aspas = false
        var corte = linha.endIndex
        for i in linha.indices {
            if linha[i] == "\"" { aspas.toggle() }
            if linha[i] == ":" && !aspas { corte = i; break }
        }
        let valor = corte < linha.endIndex ? String(linha[linha.index(after: corte)...]) : ""
        let partes = linha[..<corte].split(separator: ";")
        let nome = partes.first.map { $0.uppercased() } ?? ""
        var parametros: [String: String] = [:]
        for p in partes.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { parametros[kv[0].uppercased()] = kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return (nome, parametros, valor)
    }

    private static func evento(_ c: [String: (parametros: [String: String], valor: String)], fonte: Seguido,
                               fusoLocal: TimeZone) -> EventoInteresse? {
        // Feeds de jogos mantêm o adiado ou cancelado na lista, com STATUS:CANCELLED: sem lembrete para ele.
        guard c["STATUS"]?.valor.uppercased() != "CANCELLED",
              let dt = c["DTSTART"], let (inicio, diaInteiro) = data(dt.valor, parametros: dt.parametros, fusoLocal: fusoLocal)
        else { return nil }
        let titulo = Atividade.limpo(texto(c["SUMMARY"]?.valor ?? ""), ate: 60)
        guard !titulo.isEmpty else { return nil }
        let uid = (c["UID"]?.valor ?? titulo).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
        // Id curto: vai no id da atividade, que tem teto de 64. A data entra porque o UID se repete em recorrências.
        // O fim do UID, não o começo: os do Outlook começam todos com o mesmo prefixo longo.
        return EventoInteresse(id: "ics-\(Int(inicio.timeIntervalSince1970))-\(String(String.UnicodeScalarView(uid.suffix(16))))",
                               titulo: titulo, inicio: inicio, diaInteiro: diaInteiro, fonte: fonte)
    }

    /// `20261122T180000Z` (UTC), `20261122T130000` com `TZID=` ou sem (hora local), `VALUE=DATE:20261122` (dia inteiro).
    // ponytail: TZID que não é do banco IANA (o Outlook usa "Eastern Standard Time") cai no fuso do Mac.
    static func data(_ valor: String, parametros: [String: String], fusoLocal: TimeZone) -> (Date, Bool)? {
        let digitos = valor.filter(\.isNumber)
        let utc = valor.hasSuffix("Z")
        let diaInteiro = parametros["VALUE"]?.uppercased() == "DATE" || (digitos.count == 8 && !valor.contains("T"))
        guard digitos.count == (diaInteiro ? 8 : 14) else { return nil }
        let n = Array(digitos)
        func numero(_ de: Int, _ ate: Int) -> Int? { Int(String(n[de..<ate])) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc ? TimeZone(identifier: "UTC")! : parametros["TZID"].flatMap(TimeZone.init(identifier:)) ?? fusoLocal
        var d = DateComponents(year: numero(0, 4), month: numero(4, 6), day: numero(6, 8))
        if !diaInteiro { (d.hour, d.minute, d.second) = (numero(8, 10), numero(10, 12), numero(12, 14)) }
        if diaInteiro { cal.timeZone = fusoLocal }  // dia inteiro é "flutuante": o dia de quem olha
        guard let data = cal.date(from: d) else { return nil }
        return (data, diaInteiro)
    }

    /// O nome que o calendário se dá (`X-WR-CALNAME`, o do Google e do Calendário da Apple), limpo como um título:
    /// é o que os Ajustes e a box mostram no lugar do host. Dado de fora: `Text(verbatim:)`, nunca no log.
    static func nome(de texto: String) -> String? {
        for linha in texto.split(whereSeparator: \.isNewline).prefix(50) {  // fica no cabeçalho, antes dos eventos
            let (nome, _, valor) = propriedade(String(linha))
            if nome == "BEGIN" && valor.uppercased() == "VEVENT" { return nil }
            guard nome == "X-WR-CALNAME" else { continue }
            let limpo = Atividade.limpo(Self.texto(valor), ate: 40)
            return limpo.isEmpty ? nil : limpo
        }
        return nil
    }

    /// Escapes de TEXT (RFC 5545 3.3.11): `\,` `\;` `\\` e `\n`.
    static func texto(_ bruto: String) -> String {
        var saida = ""
        var escape = false
        for c in bruto {
            if escape {
                saida.append(c == "n" || c == "N" ? " " : c)  // quebra vira espaço: a ilha tem uma linha só
                escape = false
            } else if c == "\\" {
                escape = true
            } else {
                saida.append(c)
            }
        }
        return saida
    }
}

// MARK: Rede

/// Download com as regras do AGENTS (regra 8): só HTTPS, host conhecido também depois de redirecionamento,
/// timeout e teto de tamanho cortando no meio.
enum RedeInteresses {
    /// Efêmera: o endereço de um ICS pode ter token secreto, e a sessão compartilhada o guardaria no cache em disco.
    private static let sessao: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// O host da resposta tem de ser o do pedido: redirecionar para outro lugar é recusado.
    static func aceitar(_ resposta: URLResponse, host: String, teto: Int) -> Bool {
        guard let http = resposta as? HTTPURLResponse, http.statusCode == 200, let url = http.url else { return false }
        return url.scheme?.lowercased() == "https" && url.host() == host && http.expectedContentLength <= Int64(teto)
    }

    /// Recusa o redirecionamento antes de seguir: conferir só a resposta final já teria mandado o pedido para o
    /// outro host (um ICS colado que redireciona para um endereço da rede local, por exemplo).
    private final class SoMesmoHost: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            guard let destino = request.url, destino.scheme?.lowercased() == "https",
                  destino.host() == task.originalRequest?.url?.host() else { return nil }
            return request
        }
    }

    static func baixar(_ url: URL, teto: Int) async -> Data? {
        guard url.scheme?.lowercased() == "https", let host = url.host() else { return nil }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 15
        do {
            let (bytes, resposta) = try await sessao.bytes(for: pedido, delegate: SoMesmoHost())
            guard aceitar(resposta, host: host, teto: teto) else { return nil }
            var dados = Data()
            // Corta no meio: um servidor que não diz o tamanho (ou mente) não enche a memória.
            for try await byte in bytes {
                dados.append(byte)
                if dados.count > teto { return nil }
            }
            return dados
        } catch {
            return nil
        }
    }

    /// Os eventos de uma fonte, ou nil se a rede falhou (aí os de antes continuam valendo).
    /// Os eventos e, num calendário colado, o nome que ele mesmo se dá (`X-WR-CALNAME`).
    static func ler(_ seguido: Seguido) async -> (eventos: [EventoInteresse], nome: String?)? {
        switch seguido {
        case let .espnTime(esporte, liga, time, _):
            guard let url = ESPN.urlAgenda(esporte: esporte, liga: liga, time: time), url.host() == ESPN.host,
                  let dados = await baixar(url, teto: ESPN.tamanhoMaximo) else { return nil }
            return ESPN.jogos(de: dados, time: time, fonte: seguido).map { ($0, nil) }
        case .f1:
            guard let url = ESPN.urlF1, let dados = await baixar(url, teto: ESPN.tamanhoMaximo) else { return nil }
            return ESPN.corridas(de: dados).map { ($0, nil) }
        case .ics(let url):
            guard seguido.valido, let dados = await baixar(url, teto: ICS.tamanhoMaximo) else { return nil }
            // ponytail: o endereço (que pode ter token) fica no UserDefaults em texto puro; Keychain se virar problema.
            let texto = String(decoding: dados, as: UTF8.self)
            return ICS.eventos(de: texto, fonte: seguido).map { ($0, ICS.nome(de: texto)) }
        case .categoria(let c) where c.ligaESPN != nil:
            guard let url = c.ligaESPN.flatMap(ESPN.urlCorridas), let dados = await baixar(url, teto: ESPN.tamanhoMaximo)
            else { return nil }
            return ESPN.corridas(de: dados, fonte: seguido).map { ($0, nil) }
        case .categoria(let c):
            guard let url = c.ics, let dados = await baixar(url, teto: ICS.tamanhoMaximo),
                  let eventos = ICS.eventos(de: String(decoding: dados, as: UTF8.self), fonte: seguido) else { return nil }
            return (Categoria.marcar(eventos), nil)
        }
    }
}

// MARK: Interesses

/// Jogos e eventos que a pessoa segue fora do calendário: a linha da ilha aberta e os lembretes no `Mural`.
@MainActor @Observable
final class Interesses {
    static let chaveSeguidos = "interesses.seguidos"
    static let chaveDisparados = "interesses.disparados"
    static let maximoSeguidos = 10
    /// Agenda de jogo muda pouco: horário definido semanas antes, às vezes um adiamento.
    private static let intervalo: Duration = .seconds(6 * 3600)

    private(set) var seguidos: [Seguido] = []
    /// O próximo de cada fonte, até cinco: as páginas da box (`WidgetInteresse`).
    private(set) var proximos: [EventoInteresse] = []
    /// O próximo de cada fonte sem contar treinos e classificação: na página da F1 com um treino, a corrida no pé.
    private(set) var principais: [EventoInteresse] = []
    /// O nome que cada calendário colado se dá: "Porsche Cup 2027" em vez de "calendar.google.com". Só da sessão:
    /// volta na primeira leitura depois de abrir o app.
    private(set) var nomes: [Seguido: String] = [:]
    /// A página que a box mostra. Só da sessão: ao abrir o app, a box começa no que vem primeiro.
    var fonteNaBox: Seguido?
    /// Os placares dos jogos e corridas seguidos que estão acontecendo agora, até dois, o que começou antes
    /// primeiro (`Placar.swift`); vazio fora de jogo.
    private(set) var aoVivo: [Placar] = []

    @ObservationIgnored private let mural: Mural
    /// Os que já deram "Fim de jogo": não avisam de novo nem voltam a ser consultados. Só da sessão: depois de
    /// reiniciar, a agenda da ESPN já não traz jogo terminado.
    @ObservationIgnored private var encerrados: Set<String> = []
    /// Jogos que já tiveram placar: esses são consultados a cada minuto até acabar, mesmo se uma consulta falhar.
    @ObservationIgnored private var comPlacar: Set<String> = []
    @ObservationIgnored private var placar: Task<Void, Never>?
    @ObservationIgnored private var porFonte: [Seguido: [EventoInteresse]] = [:]
    @ObservationIgnored private var disparados: [String: Date] = [:]
    @ObservationIgnored private var ciclo: Task<Void, Never>?
    @ObservationIgnored private var relogio: Task<Void, Never>?
    @ObservationIgnored private var despertar: (any NSObjectProtocol)?

    init(mural: Mural) {
        self.mural = mural
    }

    /// Para o Toggle dos Ajustes.
    var segueF1: Bool {
        get { seguidos.contains(.f1) }
        set { newValue ? adicionar(.f1) : remover(.f1) }
    }

    func iniciar() {
        guard relogio == nil else { return }
        let padroes = UserDefaults.standard
        if let dados = padroes.data(forKey: Self.chaveSeguidos) {
            seguidos = Self.lerSeguidos(dados)
        } else {
            seguidos = [.bills]  // só na primeira vez: lista vazia de propósito continua vazia
            salvar()
        }
        disparados = (padroes.dictionary(forKey: Self.chaveDisparados) as? [String: Double] ?? [:])
            .mapValues { Date(timeIntervalSince1970: $0) }
        // Ao acordar, os lembretes podem ter dormido no meio da janela: confere já. A agenda espera o Wi-Fi voltar.
        despertar = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.conferir()
                self?.agendar(daqui: .seconds(10))
            }
        }
        agendar(daqui: .zero)
        relogio = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.conferir()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        placar = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.acompanharPlacar()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// O nome para os Ajustes e a box: o do calendário quando ele tem um, senão o de `Seguido.nome`.
    func nome(de seguido: Seguido) -> String { nomes[seguido] ?? seguido.nome }

    /// Um por um: um item que não decodifica (versão mais nova do app, categoria que saiu) cai sozinho, sem levar
    /// os times seguidos junto no próximo `salvar()`.
    static func lerSeguidos(_ dados: Data) -> [Seguido] {
        struct Talvez: Decodable {
            let valor: Seguido?
            init(from decoder: any Decoder) throws { valor = try? Seguido(from: decoder) }
        }
        return ((try? JSONDecoder().decode([Talvez].self, from: dados)) ?? []).compactMap(\.valor).filter(\.valido)
    }

    func adicionar(_ seguido: Seguido) {
        guard seguido.valido, !seguidos.contains(seguido), seguidos.count < Self.maximoSeguidos else { return }
        seguidos.append(seguido)
        salvar()
        agendar(daqui: .zero)
    }

    func remover(_ seguido: Seguido) {
        seguidos.removeAll { $0 == seguido }
        porFonte[seguido] = nil
        nomes[seguido] = nil
        if fonteNaBox == seguido { fonteNaBox = nil }
        let restantes = seguidos.flatMap { porFonte[$0] ?? [] }
        aoVivo.removeAll { p in !restantes.contains(where: p.eDo) }
        salvar()
        conferir()
    }

    /// Times da liga cujo nome contém a busca. Vazio se nada bate ou se a rede falhou.
    func buscarTimes(_ nome: String, liga: Liga) async -> [Seguido] {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty, nome.count <= 60, let url = ESPN.urlTimes(liga),
              let dados = await RedeInteresses.baixar(url, teto: ESPN.tamanhoMaximo) else {
            registro.notice("interesses: busca de times sem rede ou vazia")
            return []
        }
        let achados = ESPN.times(de: dados, liga: liga, busca: nome)
        registro.info("interesses: \(achados.count) times encontrados")
        return achados
    }

    /// O clique no lembrete ou na linha da ilha: a página do jogo na ESPN. Evento de calendário ICS não tem página.
    func abrir(_ evento: EventoInteresse) {
        guard let link = evento.link, link.scheme == "https", link.host() == "www.espn.com" else { return }
        NSWorkspace.shared.open(link)
    }

    private func salvar() {
        if let json = try? JSONEncoder().encode(seguidos) { UserDefaults.standard.set(json, forKey: Self.chaveSeguidos) }
    }

    private func agendar(daqui espera: Duration) {
        ciclo?.cancel()
        ciclo = Task { [weak self] in
            var espera = espera
            var tentativas = 0
            while true {
                try? await Task.sleep(for: espera)
                guard !Task.isCancelled, let self else { return }
                // Falhou (o Mac ligou antes do Wi-Fi, por exemplo): tenta de novo logo, sem esperar 6 horas
                // e perder a véspera e a 1 hora de um jogo nesse meio.
                if await self.atualizar() {
                    tentativas = 0
                    espera = Interesses.intervalo
                } else {
                    espera = .seconds(min(60 * (1 << min(tentativas, 4)), 900))
                    tentativas += 1
                }
            }
        }
    }

    // ponytail: uma fonte de cada vez; com 10 fontes no máximo e de 6 em 6 horas, paralelo não muda nada.
    /// true quando todas as fontes responderam.
    private func atualizar() async -> Bool {
        let inicio = ContinuousClock.now
        var falharam = 0
        for seguido in seguidos {
            guard let lido = await RedeInteresses.ler(seguido) else { falharam += 1; continue }
            // A pessoa pode ter tirado a fonte enquanto a resposta vinha.
            guard seguidos.contains(seguido) else { continue }
            porFonte[seguido] = lido.eventos
            if nomes[seguido] != lido.nome { nomes[seguido] = lido.nome }
        }
        let total = porFonte.values.reduce(0) { $0 + $1.count }
        registro.info("interesses: \(total) eventos de \(self.seguidos.count) fontes, \(falharam) sem rede (\(ContinuousClock.now - inicio, privacy: .public))")
        conferir()
        return falharam == 0
    }

    /// Recalcula o próximo e manda os lembretes devidos. Roda a cada minuto, ao acordar e depois de cada busca.
    private func conferir() {
        let agora = Date.now
        var vistos = Set<String>()
        // O mesmo jogo vem duas vezes quando a pessoa segue os dois times.
        let eventos = seguidos.flatMap { porFonte[$0] ?? [] }.filter { vistos.insert($0.id).inserted }
        let novos = Placar.comAoVivo(EventoInteresse.proximos(eventos, agora: agora), eventos: eventos, aoVivo: aoVivo)
        if novos != proximos { proximos = novos }
        let corridas = EventoInteresse.proximos(eventos.filter { $0.sessao == nil }, agora: agora, maximo: Interesses.maximoSeguidos)
        if corridas != principais { principais = corridas }

        // No máximo três por minuto, o mais perto de começar primeiro: um calendário com 20 eventos na semana
        // encheria a ilha (máximo 8) e empurraria o resto para fora. Os outros saem nos minutos seguintes.
        let devidos = EventoInteresse.lembretes(eventos, agora: agora, disparados: Set(disparados.keys))
            .sorted { $0.evento.inicio < $1.evento.inicio }
            .prefix(Mural.maximoAvisos)
        for lembrete in devidos {
            disparados[lembrete.chave] = lembrete.evento.inicio
            let e = lembrete.evento
            // O de 1 hora fica até o início (o Mural corta em 1 hora, que é o que falta); os outros, 10 s.
            let expira = lembrete.tipo == .umaHora ? max(e.inicio.timeIntervalSince(agora), 1) : Atividade.expiraPadrao
            mural.receber(Atividade(id: "interesse-\(lembrete.chave)", titulo: e.titulo,
                                    // O de 1 hora fica até o início: "em 1 hora" ficaria parado; a hora não envelhece.
                                    // Um jogo à 00:30 tem o lembrete às 23:30 da véspera: aí é "amanhã", não "hoje".
                                    detalhe: lembrete.tipo == .umaHora
                                        ? EventoInteresse.diaEHora(e, agora: agora)
                                        : EventoInteresse.quando(e, agora: agora),
                                    simbolo: e.fonte.simbolo, cor: e.fonte.cor, expira: expira,
                                    prioridade: lembrete.tipo == .umaHora ? "alta" : "normal")) { [weak self] in self?.abrir(e) }
        }
        let podados = EventoInteresse.podar(disparados, agora: agora)
        if !devidos.isEmpty || podados.count != disparados.count {
            disparados = podados
            UserDefaults.standard.set(disparados.mapValues(\.timeIntervalSince1970), forKey: Self.chaveDisparados)
        }
        if !devidos.isEmpty { registro.info("interesses: \(devidos.count) lembretes de \(eventos.count) eventos") }
    }

    /// A cada minuto, mas só vai à rede com um jogo ou corrida seguidos na janela do `Placar`. Ao terminar, o
    /// resultado vira atividade e sai de `aoVivo` na hora: o placar final já está nas asas pelo mural, mostrá-lo
    /// também ali repetiria.
    // ponytail: dois ao vivo no máximo (`Placar.maximoAoVivo`); um terceiro ao mesmo tempo ganha o "Fim de jogo",
    // mas só aparece ao vivo quando um dos dois acabar.
    private func acompanharPlacar() async {
        let agora = Date.now
        let naJanela = Placar.emJogo(seguidos.flatMap { porFonte[$0] ?? [] }, agora: agora, encerrados: encerrados)
        guard !naJanela.isEmpty else {
            if !aoVivo.isEmpty { aoVivo = []; conferir() }
            return
        }
        // Meia hora depois do início e ainda sem placar (atrasado pela chuva, adiado ou cancelado, que `ler` não
        // distingue de "ainda não começou"): consulta a cada 5 min em vez de a cada minuto, sem nunca dar o jogo por
        // encerrado. Uma falha passageira de uma das ligas não pode apagar o placar até reabrir o app.
        let minuto = Int(agora.timeIntervalSince1970 / 60)
        let jogos = naJanela.filter { e in
            agora.timeIntervalSince(e.inicio) < 1800 || minuto % 5 == 0 || Placar.idESPN(e).map(comPlacar.contains) == true
        }
        guard !jogos.isEmpty, let resposta = await Placar.buscar(jogos) else { return }  // sem rede: o último placar fica
        // Deixou de seguir o time durante a consulta: o placar dele não volta para a ilha.
        let seguidosAgora = seguidos.flatMap { porFonte[$0] ?? [] }
        let placares = resposta.placares.filter { p in seguidosAgora.contains(where: p.eDo) }
        comPlacar.formUnion(placares.map(\.eventoId))
        for p in placares where p.encerrado && !encerrados.contains(p.eventoId) {
            encerrados.insert(p.eventoId)
            guard let e = jogos.first(where: p.eDo) else { continue }
            // 10 min: dá para ver o resultado, sem tirar o timer da asa por meia hora (`asaAtual`).
            // Na corrida o título é a ponta ("1 NOR · 2 VER · 3 HAD"): o vencedor vem primeiro.
            mural.receber(Atividade(id: "placar-\(p.eventoId)", titulo: p.texto, detalhe: p.fim,
                                    simbolo: e.fonte.simbolo, cor: e.fonte.cor, expira: 600,
                                    prioridade: "normal")) { [weak self] in self?.abrir(e) }
        }
        // Os que saíram da janela também saem daqui: `naJanela` é recalculada a cada minuto.
        let novo = Placar.aoVivo(lidos: placares, consultados: resposta.consultados, antes: aoVivo, naJanela: naJanela)
        if novo != aoVivo {
            // Um jogo que começou agora vira a página da box: "Ao vivo" numa página escondida não serve.
            if let comecou = novo.first(where: { p in !aoVivo.contains { $0.eventoId == p.eventoId } }),
               let fonte = jogos.first(where: comecou.eDo)?.fonte {
                fonteNaBox = fonte
            }
            aoVivo = novo
            conferir()
        }
        registro.info("interesses: placar de \(jogos.count) jogos, \(placares.count) lidos")
    }
}
