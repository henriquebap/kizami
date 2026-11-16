import Foundation

// O tempo: código WMO → símbolo, leitura das respostas do Open-Meteo (com a forma das respostas reais) e as URLs.
@MainActor func testarTempo() {
    conferir("céu limpo de dia", Previsao.simbolo(codigo: 0, dia: true), "sun.max.fill")
    conferir("céu limpo à noite", Previsao.simbolo(codigo: 0, dia: false), "moon.stars.fill")
    conferir("poucas nuvens à noite", Previsao.simbolo(codigo: 2, dia: false), "cloud.moon.fill")
    conferir("nublado não muda à noite", Previsao.simbolo(codigo: 3, dia: false), "cloud.fill")
    conferir("garoa", Previsao.simbolo(codigo: 51, dia: true), "cloud.drizzle.fill")
    conferir("trovoada", Previsao.simbolo(codigo: 95, dia: true), "cloud.bolt.rain.fill")
    conferir("código desconhecido: termômetro", Previsao.simbolo(codigo: 42, dia: true), "thermometer.medium")
    conferir("código desconhecido: sem descrição", Previsao.descricao(codigo: 42), nil)
    conferir("graus arredondados", Previsao.graus(23.5), "24°")
    conferir("sem -0°", Previsao.graus(-0.4), "0°")

    // Resposta real de São Paulo (16/11/2026), cortada nos campos que a gente pede.
    let previsaoReal = """
        {"latitude":-23.514938,"longitude":-46.610504,"timezone":"America/Sao_Paulo",
        "current":{"time":"2026-11-16T14:15","interval":900,"temperature_2m":23.3,"weather_code":51,"is_day":1},
        "daily":{"time":["2026-11-16"],"temperature_2m_max":[24.5],"temperature_2m_min":[18.4],
        "precipitation_probability_max":[100]}}
        """
    let agora = Date(timeIntervalSince1970: 1_800_000_000)
    conferir("lê a previsão real", OpenMeteo.previsao(de: Data(previsaoReal.utf8), obtida: agora),
             Previsao(temperatura: 23.3, maxima: 24.5, minima: 18.4, chuva: 100, codigo: 51, dia: true, obtida: agora))
    func previsao(_ atual: Double, codigo: Int = 0, chuva: String = "[10]") -> Previsao? {
        let json = """
            {"current":{"temperature_2m":\(atual),"weather_code":\(codigo),"is_day":0},
            "daily":{"temperature_2m_max":[28],"temperature_2m_min":[19],"precipitation_probability_max":\(chuva)}}
            """
        return OpenMeteo.previsao(de: Data(json.utf8), obtida: agora)
    }
    conferir("chance de chuva nula é aceita", previsao(20, chuva: "[null]")?.chuva, nil)
    conferir("à noite", previsao(20)?.dia, false)
    conferir("900° é descartado", previsao(900), nil)
    conferir("-120° é descartado", previsao(-120), nil)
    conferir("código WMO fora da tabela é descartado", previsao(20, codigo: 300), nil)
    conferir("chuva de 150% é descartada", previsao(20, chuva: "[150]"), nil)
    conferir("sem a parte diária é descartado",
             OpenMeteo.previsao(de: Data(#"{"current":{"temperature_2m":20,"weather_code":0,"is_day":1}}"#.utf8), obtida: agora), nil)

    // Resposta real da busca por "São Paulo" (cortada) e a de uma busca sem resultado, que vem sem `results`.
    let buscaReal = """
        {"results":[{"id":3448439,"name":"São Paulo","latitude":-23.5475,"longitude":-46.63611,"country_code":"BR",
        "country":"Brasil","admin1":"São Paulo"}],"generationtime_ms":0.19}
        """
    conferir("lê a cidade, sem repetir o estado", OpenMeteo.lugar(de: Data(buscaReal.utf8)),
             Lugar(nome: "São Paulo", latitude: -23.5475, longitude: -46.63611))
    conferir("cidade com o estado", OpenMeteo.lugar(de: Data(
        #"{"results":[{"name":"Campinas","latitude":-22.9,"longitude":-47.06,"admin1":"São Paulo"}]}"#.utf8))?.nome,
             "Campinas, São Paulo")
    conferir("busca sem resultado", OpenMeteo.lugar(de: Data(#"{"generationtime_ms":0.08}"#.utf8)), nil)
    conferir("latitude impossível é descartada", OpenMeteo.lugar(de: Data(
        #"{"results":[{"name":"X","latitude":123,"longitude":0}]}"#.utf8)), nil)

    conferir("nome da cidade codificado na URL", OpenMeteo.urlBusca("São Paulo")?.absoluteString,
             "https://geocoding-api.open-meteo.com/v1/search?name=S%C3%A3o%20Paulo&count=1&language=pt&format=json")
    conferir("& no nome não vira outro parâmetro", OpenMeteo.urlBusca("a&count=99")?.query()?.contains("count=99"), false)
    let url = OpenMeteo.urlPrevisao(Lugar(nome: "São Paulo", latitude: -23.5475, longitude: -46.63611))?.absoluteString ?? ""
    conferir("coordenadas com ponto", url.contains("latitude=-23.5475&longitude=-46.6361&"), true)
    conferir("previsão no host fixo, por HTTPS", url.hasPrefix("https://api.open-meteo.com/v1/forecast?"), true)

    let resposta = { (url: String, status: Int) in
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
    conferir("resposta boa", OpenMeteo.aceitar(Data("{}".utf8), resposta("https://api.open-meteo.com/v1/forecast", 200)), true)
    conferir("status 500", OpenMeteo.aceitar(Data("{}".utf8), resposta("https://api.open-meteo.com/v1/forecast", 500)), false)
    conferir("redirecionada para outro host", OpenMeteo.aceitar(Data("{}".utf8), resposta("https://open-meteo.com.evil.example/", 200)), false)
    conferir("HTTP sem S", OpenMeteo.aceitar(Data("{}".utf8), resposta("http://api.open-meteo.com/v1/forecast", 200)), false)
    conferir("grande demais", OpenMeteo.aceitar(Data(count: 300_000), resposta("https://api.open-meteo.com/v1/forecast", 200)), false)
}
