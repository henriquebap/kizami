import AppKit
import Observation

/// A previsão de hoje, como a ilha mostra. Só sai de `OpenMeteo.previsao(de:obtida:)`, que descarta número estranho.
struct Previsao: Equatable, Sendable {
    let temperatura: Double
    let maxima: Double
    let minima: Double
    /// Chance de chuva no dia, 0 a 100. Nil quando o Open-Meteo não tem o dado para o lugar.
    let chuva: Int?
    /// Código WMO do tempo agora.
    let codigo: Int
    let dia: Bool
    let obtida: Date

    var simbolo: String { Previsao.simbolo(codigo: codigo, dia: dia) }
    var descricao: String? { Previsao.descricao(codigo: codigo) }

    /// Símbolos com versão multicolor. Noite só muda onde o sol aparece no desenho.
    static func simbolo(codigo: Int, dia: Bool) -> String {
        switch codigo {
        case 0: dia ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: dia ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 66: "cloud.rain.fill"
        case 65, 67: "cloud.heavyrain.fill"
        case 80, 81, 82: dia ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "thermometer.medium"
        }
    }

    /// Nil para um código que a tabela WMO não tem: a dica mostra só a cidade.
    static func descricao(codigo: Int) -> String? {
        switch codigo {
        case 0: String(localized: "Céu limpo")
        case 1, 2: String(localized: "Parcialmente nublado")
        case 3: String(localized: "Nublado")
        case 45, 48: String(localized: "Neblina")
        case 51, 53, 55, 56, 57: String(localized: "Garoa")
        case 61, 63, 65, 66, 67: String(localized: "Chuva")
        case 80, 81, 82: String(localized: "Pancadas de chuva")
        case 71, 73, 75, 77, 85, 86: String(localized: "Neve")
        case 95, 96, 99: String(localized: "Trovoada")
        default: nil
        }
    }

    /// "23°", arredondado. Sem unidade: a pessoa sabe se mora em lugar de Celsius, e o espaço do chip é pouco.
    static func graus(_ valor: Double) -> String { "\(Int(valor.rounded()))°" }
}

/// O lugar escolhido nos Ajustes, como fica guardado no `UserDefaults`.
struct Lugar: Codable, Equatable, Sendable {
    let nome: String
    let latitude: Double
    let longitude: Double

    var valido: Bool {
        !nome.isEmpty && nome.count <= 100 && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// O Open-Meteo: previsão e busca de cidade, sem chave. Tudo que chega dele é dado de fora: passa pelas
/// regras daqui antes de virar `Previsao` ou `Lugar`.
enum OpenMeteo {
    static let hostPrevisao = "api.open-meteo.com"
    static let hostBusca = "geocoding-api.open-meteo.com"
    /// A resposta de verdade tem menos de 1 KB; o teto só existe para um servidor errado não encher a memória.
    static let tamanhoMaximo = 200_000
    static let temperaturas = -90.0...60.0

    // Só os campos usados. `results` falta quando a busca não acha nada (visto na resposta real).
    struct RespostaPrevisao: Decodable {
        struct Atual: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Diaria: Decodable {
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]?
        }
        let current: Atual
        let daily: Diaria
    }

    struct RespostaBusca: Decodable {
        struct Resultado: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let admin1: String?
        }
        let results: [Resultado]?
    }

    /// Coordenadas com ponto: um Mac em português formataria "-23,5475", e a API recusaria.
    static func urlPrevisao(_ lugar: Lugar) -> URL? {
        let posix = Locale(identifier: "en_US_POSIX")
        var c = URLComponents()
        c.scheme = "https"
        c.host = hostPrevisao
        c.path = "/v1/forecast"
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", locale: posix, lugar.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", locale: posix, lugar.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            // O "hoje" da máxima e da mínima é o dia do lugar, não o do fuso do Mac.
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]
        return c.url
    }

    static func urlBusca(_ nome: String) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = hostBusca
        c.path = "/v1/search"
        c.queryItems = [
            URLQueryItem(name: "name", value: nome),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "pt"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url
    }

    /// Nil se faltar campo ou algum número for implausível: melhor não mostrar nada que mostrar 900°.
    static func previsao(de dados: Data, obtida: Date) -> Previsao? {
        guard let r = try? JSONDecoder().decode(RespostaPrevisao.self, from: dados),
              let maxima = r.daily.temperature_2m_max.first ?? nil,
              let minima = r.daily.temperature_2m_min.first ?? nil,
              [r.current.temperature_2m, maxima, minima].allSatisfy({ $0.isFinite && temperaturas.contains($0) }),
              (0...99).contains(r.current.weather_code) else { return nil }
        let chuva = r.daily.precipitation_probability_max?.first ?? nil
        guard chuva.map({ (0...100).contains($0) }) ?? true else { return nil }
        return Previsao(temperatura: r.current.temperature_2m, maxima: maxima, minima: minima, chuva: chuva,
                        codigo: r.current.weather_code, dia: r.current.is_day == 1, obtida: obtida)
    }

    /// O primeiro resultado. "Campinas, São Paulo" ajuda a saber que achou a cidade certa; "São Paulo, São Paulo" não.
    static func lugar(de dados: Data) -> Lugar? {
        guard let r = try? JSONDecoder().decode(RespostaBusca.self, from: dados), let primeiro = r.results?.first,
              primeiro.latitude.isFinite, primeiro.longitude.isFinite else { return nil }
        let estado = primeiro.admin1.flatMap { $0.isEmpty || $0 == primeiro.name ? nil : $0 }
        let lugar = Lugar(nome: [primeiro.name, estado].compactMap { $0 }.joined(separator: ", "),
                          latitude: primeiro.latitude, longitude: primeiro.longitude)
        return lugar.valido ? lugar : nil
    }

    /// Só HTTPS para um dos dois hosts, também depois de redirecionamento; status 200; tamanho com teto.
    static func aceitar(_ dados: Data, _ resposta: URLResponse) -> Bool {
        guard let http = resposta as? HTTPURLResponse, http.statusCode == 200, let url = http.url else { return false }
        return doOpenMeteo(url) && dados.count <= tamanhoMaximo
    }

    static func doOpenMeteo(_ url: URL) -> Bool {
        url.scheme == "https" && [hostPrevisao, hostBusca].contains(url.host())
    }

    /// Efêmera: a cidade e as coordenadas vão na URL, e a sessão compartilhada as guardaria no cache em disco.
    // ponytail: o teto de tamanho é conferido depois de baixar; um delegate que corta no meio só se o Open-Meteo virar risco.
    private static let sessao = URLSession(configuration: .ephemeral)

    static func baixar(_ url: URL) async -> Data? {
        guard doOpenMeteo(url) else { return nil }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 10
        guard let (dados, resposta) = try? await sessao.data(for: pedido), aceitar(dados, resposta) else {
            return nil
        }
        return dados
    }
}

/// A temperatura do lugar que a pessoa digitou nos Ajustes. Sem lugar, `previsao` fica nil e o chip some.
@MainActor @Observable final class Tempo {
    static let chaveLocal = "tempo.local"
    /// O roadmap pede 30 min: a previsão do Open-Meteo não muda mais rápido que isso.
    private static let intervalo: Duration = .seconds(30 * 60)
    /// Sem rede por mais tempo que isso, a temperatura de antes já engana mais do que ajuda.
    private static let validade: TimeInterval = 3 * 60 * 60

    private(set) var previsao: Previsao?
    /// O nome do lugar para mostrar (nos Ajustes e na dica do chip).
    private(set) var local: String?
    @ObservationIgnored private var lugar: Lugar?
    @ObservationIgnored private var ciclo: Task<Void, Never>?
    @ObservationIgnored private var despertar: (any NSObjectProtocol)?

    func iniciar() {
        lugar = UserDefaults.standard.data(forKey: Self.chaveLocal)
            .flatMap { try? JSONDecoder().decode(Lugar.self, from: $0) }
            .flatMap { $0.valido ? $0 : nil }
        local = lugar?.nome
        // Depois de horas dormindo, a previsão está velha. Espera um pouco: logo ao acordar o Wi-Fi ainda não voltou.
        despertar = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.agendar(daqui: .seconds(10)) }
        }
        agendar(daqui: .zero)
    }

    /// Procura a cidade e passa a usá-la. Falso se não achou ou se a rede falhou; aí o lugar de antes continua.
    func trocarCidade(_ nome: String) async -> Bool {
        let nome = nome.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nome.isEmpty, nome.count <= 100, let url = OpenMeteo.urlBusca(nome) else { return false }
        let inicio = ContinuousClock.now
        guard let dados = await OpenMeteo.baixar(url), let novo = OpenMeteo.lugar(de: dados) else {
            registro.notice("tempo: cidade não encontrada ou sem rede (\(ContinuousClock.now - inicio, privacy: .public))")
            return false
        }
        registro.info("tempo: cidade encontrada (\(ContinuousClock.now - inicio, privacy: .public))")
        if let json = try? JSONEncoder().encode(novo) { UserDefaults.standard.set(json, forKey: Self.chaveLocal) }
        lugar = novo
        local = novo.nome
        previsao = nil  // a temperatura de outra cidade não pode ficar à vista com o nome da nova
        agendar(daqui: .zero)
        return true
    }

    func esquecerCidade() {
        UserDefaults.standard.removeObject(forKey: Self.chaveLocal)
        ciclo?.cancel()
        lugar = nil
        local = nil
        previsao = nil
    }

    private func agendar(daqui espera: Duration) {
        ciclo?.cancel()
        guard lugar != nil else { return }
        ciclo = Task { [weak self] in
            var espera = espera
            while true {
                try? await Task.sleep(for: espera)
                guard !Task.isCancelled, let self else { return }
                await self.atualizar()
                espera = Tempo.intervalo
            }
        }
    }

    private func atualizar() async {
        guard let pedido = lugar, let url = OpenMeteo.urlPrevisao(pedido) else { return }
        let inicio = ContinuousClock.now
        let nova = await OpenMeteo.baixar(url).flatMap { OpenMeteo.previsao(de: $0, obtida: .now) }
        // A pessoa pode ter trocado de cidade enquanto a resposta vinha.
        guard lugar == pedido else { return }
        if let nova {
            registro.info("tempo: previsão obtida (\(ContinuousClock.now - inicio, privacy: .public))")
            previsao = nova
        } else {
            registro.notice("tempo: previsão indisponível (\(ContinuousClock.now - inicio, privacy: .public))")
            if let velha = previsao, Date.now.timeIntervalSince(velha.obtida) > Self.validade { previsao = nil }
        }
    }
}
