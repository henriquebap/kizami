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

    // Forma da resposta real com `minutely_15` e `timeformat=unixtime` (São Paulo, 17/11/2026 00:37), com chuva
    // posta nos quartos de hora 01:15 e 01:30. Cada valor é a soma dos 15 min anteriores ao horário.
    let comQuinze = """
        {"timezone":"America/Sao_Paulo","current":{"time":1794886200,"interval":900,"temperature_2m":19.0,"weather_code":3,"is_day":0},
        "minutely_15_units":{"time":"unixtime","precipitation":"mm"},
        "minutely_15":{"time":[1794886200,1794887100,1794888000,1794888900,1794889800,1794890700,1794891600,1794892500],
        "precipitation":[0.00,0.00,0.10,0.40,1.20,0.00,0.00,0.00]},
        "daily":{"time":[1794884400],"temperature_2m_max":[27.6],"temperature_2m_min":[18.1],"precipitation_probability_max":[9]}}
        """
    let as0037 = Date(timeIntervalSince1970: 1_794_886_620)
    // 1794888900 é 01:15 (soma de 01:00 a 01:15): a chuva começa às 01:00, 23 min depois.
    conferir("chuva chegando na resposta", OpenMeteo.previsao(de: Data(comQuinze.utf8), obtida: as0037)?.chuvaAs,
             Date(timeIntervalSince1970: 1_794_888_000))
    conferir("resposta sem minutely_15: sem aviso", previsao(20)?.chuvaAs, nil)
    conferir("resposta sem minutely_15 ainda vale", previsao(20)?.temperatura, 20)
    let torta = comQuinze.replacingOccurrences(of: "0.00,0.00]}", with: "0.00]}")
    conferir("série com tamanhos diferentes: sem aviso, com temperatura",
             OpenMeteo.previsao(de: Data(torta.utf8), obtida: as0037).map { [$0.chuvaAs == nil, $0.temperatura == 19] }, [true, true])
    let negativa = comQuinze.replacingOccurrences(of: "0.40", with: "-5")
    conferir("chuva negativa invalida a série", OpenMeteo.previsao(de: Data(negativa.utf8), obtida: as0037)?.chuvaAs, nil)

    // A regra do aviso: quartos de hora a partir das 14:00 (em segundos desde `base`).
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func serie(_ mm: [Double]) -> [(inicio: Date, mm: Double)] {
        mm.enumerated().map { (inicio: base + Double($0.offset) * 900, mm: $0.element) }
    }
    let as1405 = base + 5 * 60
    conferir("série vazia", Previsao.chuvaChegando([], agora: as1405), nil)
    conferir("chuva às 14:30", Previsao.chuvaChegando(serie([0, 0, 0.5, 1]), agora: as1405), base + 30 * 60)
    conferir("já chovendo: não avisa", Previsao.chuvaChegando(serie([0.5, 0, 1]), agora: as1405), nil)
    conferir("choveu e parou: avisa a próxima", Previsao.chuvaChegando(serie([0.5, 0, 1]), agora: base + 20 * 60), base + 30 * 60)
    conferir("garoa abaixo do limiar", Previsao.chuvaChegando(serie([0, 0.1, 0.19, 0]), agora: as1405), nil)
    conferir("no limiar avisa", Previsao.chuvaChegando(serie([0, 0.2]), agora: as1405), base + 15 * 60)
    conferir("depois da próxima hora não avisa", Previsao.chuvaChegando(serie([0, 0, 0, 0, 0, 3]), agora: as1405), nil)
    conferir("horários passados não contam", Previsao.chuvaChegando(serie([2, 0]), agora: base + 40 * 60), nil)
    conferir("fora de ordem: a primeira", Previsao.chuvaChegando(Array(serie([0, 0, 1, 1]).reversed()), agora: as1405),
             base + 30 * 60)

    // Um aviso por episódio.
    let chega = base + 30 * 60
    func episodio(_ chega: Date?, _ avisada: Date?, _ agora: Date) -> [String] {
        let r = Tempo.episodio(chega: chega, avisada: avisada, agora: agora)
        return [r.avisada.map { "\(Int($0.timeIntervalSince(base)) / 60)" } ?? "nil", r.publicar ? "publica" : "quieto"]
    }
    conferir("primeira chuva: publica", episodio(chega, nil, as1405), ["30", "publica"])
    conferir("mesma chuva na atualização seguinte: quieto", episodio(chega, chega, base + 20 * 60), ["30", "quieto"])
    conferir("chuva adiada: não repete", episodio(chega + 900, chega, base + 35 * 60), ["30", "quieto"])
    conferir("previsão desistiu antes da hora: guarda", episodio(nil, chega, base + 20 * 60), ["30", "quieto"])
    conferir("choveu e passou: esquece", episodio(nil, chega, base + 50 * 60), ["nil", "quieto"])
    conferir("hora depois do avisado: nova chuva avisa", episodio(base + 2 * 3600, chega, base + 95 * 60), ["120", "publica"])

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
    conferir("URL pede a série de 15 min", url.contains("minutely_15=precipitation&forecast_minutely_15=8&timeformat=unixtime"), true)

    conferir("URL pede as horas do dia", url.contains("hourly=temperature_2m,precipitation_probability"), true)
    testarHoras()

    let resposta = { (url: String, status: Int) in
        HTTPURLResponse(url: URL(string: url)!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
    conferir("resposta boa", OpenMeteo.aceitar(Data("{}".utf8), resposta("https://api.open-meteo.com/v1/forecast", 200)), true)
    conferir("status 500", OpenMeteo.aceitar(Data("{}".utf8), resposta("https://api.open-meteo.com/v1/forecast", 500)), false)
    conferir("redirecionada para outro host", OpenMeteo.aceitar(Data("{}".utf8), resposta("https://open-meteo.com.evil.example/", 200)), false)
    conferir("HTTP sem S", OpenMeteo.aceitar(Data("{}".utf8), resposta("http://api.open-meteo.com/v1/forecast", 200)), false)
    conferir("grande demais", OpenMeteo.aceitar(Data(count: 300_000), resposta("https://api.open-meteo.com/v1/forecast", 200)), false)
}

/// A série de hora em hora (forma da resposta real de São Paulo, 17/11/2026) e as faixas de chuva da linha do tempo.
@MainActor func testarHoras() {
    var sp = Calendar(identifier: .gregorian)
    sp.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    let meiaNoite = Date(timeIntervalSince1970: 1_794_884_400)  // 17/11/2026 0 h em São Paulo
    let h = { (hora: Double) in meiaNoite.addingTimeInterval(hora * 3600) }
    func resposta(_ horaria: String) -> String {
        """
        {"current":{"time":1794950100,"interval":900,"temperature_2m":22.3,"weather_code":2,"is_day":1},
        "hourly_units":{"time":"unixtime","temperature_2m":"°C","precipitation_probability":"%"},
        "hourly":\(horaria),
        "daily":{"time":[1794884400],"temperature_2m_max":[28.0],"temperature_2m_min":[18.1],"precipitation_probability_max":[4]}}
        """
    }
    func horas(_ horaria: String) -> [HoraPrevista]? {
        OpenMeteo.previsao(de: Data(resposta(horaria).utf8), obtida: meiaNoite)?.horas
    }
    let real = #"{"time":[1794884400,1794888000,1794891600],"temperature_2m":[18.3,18.1,18.2],"precipitation_probability":[0,null,60]}"#
    conferir("horas: lê a série", horas(real), [
        HoraPrevista(hora: h(0), temperatura: 18.3, chuva: 0), HoraPrevista(hora: h(1), temperatura: 18.1, chuva: nil),
        HoraPrevista(hora: h(2), temperatura: 18.2, chuva: 60),
    ])
    conferir("horas: temperatura nula fica de fora",
             horas(#"{"time":[1794884400,1794888000],"temperature_2m":[null,18.1],"precipitation_probability":[0,0]}"#)?.map(\.hora), [h(1)])
    conferir("horas: sem chance de chuva, só a temperatura",
             horas(#"{"time":[1794884400],"temperature_2m":[18.3]}"#), [HoraPrevista(hora: h(0), temperatura: 18.3, chuva: nil)])
    conferir("horas: tamanhos diferentes = vazia, com temperatura",
             OpenMeteo.previsao(de: Data(resposta(#"{"time":[1794884400],"temperature_2m":[18.3,1],"precipitation_probability":[0]}"#).utf8),
                                obtida: meiaNoite).map { [$0.horas.isEmpty, $0.temperatura == 22.3] }, [true, true])
    conferir("horas: 900° = vazia",
             horas(#"{"time":[1794884400],"temperature_2m":[900],"precipitation_probability":[0]}"#), [])
    conferir("horas: chance de 150% = vazia",
             horas(#"{"time":[1794884400],"temperature_2m":[18],"precipitation_probability":[150]}"#), [])
    conferir("horas: resposta sem hourly ainda vale", horas("null"), [])

    // Faixas: a chance de cada horário vale para a hora que termina nele.
    func serie(_ chances: [Int?]) -> [HoraPrevista] {
        chances.enumerated().map { HoraPrevista(hora: h(Double($0.offset)), temperatura: 20, chuva: $0.element) }
    }
    func faixas(_ chances: [Int?]) -> [FaixaDeChuva] { Previsao.faixasDeChuva(serie(chances), dia: h(12), calendario: sp) }
    var chances = [Int?](repeating: 0, count: 24)
    conferir("faixas: dia seco", faixas(chances), [])
    chances[14] = 50; chances[15] = 80; chances[16] = 60; chances[18] = 70
    conferir("faixas: horas seguidas viram uma, com a maior chance", faixas(chances), [
        FaixaDeChuva(inicio: h(13), fim: h(16), maxima: 80), FaixaDeChuva(inicio: h(17), fim: h(18), maxima: 70),
    ])
    chances = [Int?](repeating: 0, count: 24)
    chances[13] = 49; chances[14] = nil
    conferir("faixas: abaixo de 50 e sem dado não listram", faixas(chances), [])
    chances = [Int?](repeating: 90, count: 24)
    conferir("faixas: cortada nas 8 h e nas 20 h", faixas(chances), [FaixaDeChuva(inicio: h(8), fim: h(20), maxima: 90)])
    chances = [Int?](repeating: 0, count: 24)
    chances[8] = 95; chances[9] = 55; chances[20] = 60; chances[21] = 100
    conferir("faixas: o que cai fora da janela não entra nem na máxima", faixas(chances), [
        FaixaDeChuva(inicio: h(8), fim: h(9), maxima: 55), FaixaDeChuva(inicio: h(19), fim: h(20), maxima: 60),
    ])
    conferir("faixas: fora de ordem", Previsao.faixasDeChuva(serie([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 70, 70]).reversed(), dia: h(12), calendario: sp),
             [FaixaDeChuva(inicio: h(9), fim: h(11), maxima: 70)])
}
