import AppKit

/// Comandos de mídia para o Music e o Spotify, pela mesma permissão de Automação da capa.
/// Navegadores não têm comando público: lá a ilha mostra só as barras.
// ponytail: para controlar também o navegador (YouTube), mandar as teclas de mídia do sistema, o que pede
// a permissão de Acessibilidade.
enum Controle {
    enum Acao: String, CaseIterable {
        case anterior = "previous track"
        case alternar = "playpause"
        case proxima = "next track"
    }

    private static let nomes = [Som.music: "Music", Som.spotify: "Spotify"]

    static func sabeControlar(_ app: String) -> Bool { nomes[app] != nil }

    /// O script de uma ação, ou nil para um app que não se controla assim. Tudo nele vem de listas fixas.
    /// O `is running` vem antes do `tell`: falar com um app fechado abriria o app.
    static func script(_ acao: Acao, app: String) -> String? {
        nomes[app].map { "if application \"\($0)\" is running then tell application \"\($0)\" to \(acao.rawValue)" }
    }

    static func enviar(_ acao: Acao, app: String) {
        guard let script = script(acao, app: app) else { return }
        Task { _ = await AppleScript.rodar(script) }
    }
}

/// A capa da faixa que está tocando, pedida ao próprio player por AppleScript. Na primeira vez, o macOS pergunta
/// se o Kizami pode controlar o Music ou o Spotify (Automação); negado, a miniatura fica sendo o ícone do app.
/// Nenhum texto de fora entra nos scripts: eles são fixos, só o caminho do arquivo temporário (um UUID nosso) muda.
enum Capa {
    static func sabeBuscar(_ app: String) -> Bool {
        app == Som.music || app == Som.spotify
    }

    /// `faixa` é a chave que o player anunciou. Tenta de novo uma vez: logo depois da troca de faixa, o Music
    /// ainda pode não ter a capa carregada, e o Spotify ainda responde com a faixa anterior.
    static func buscar(app: String, faixa: String) async -> NSImage? {
        var imagem = await tentar(app: app, faixa: faixa)
        if imagem == nil {
            try? await Task.sleep(for: .seconds(1.5))
            imagem = await tentar(app: app, faixa: faixa)
        }
        registro.info("capa: \(imagem == nil ? "indisponível" : "obtida", privacy: .public)")
        return imagem
    }

    private static func tentar(app: String, faixa: String) async -> NSImage? {
        switch app {
        case Som.music: await doMusic()
        case Som.spotify: await doSpotify(faixa: faixa)
        default: nil
        }
    }

    /// O Music entrega os bytes da imagem; o AppleScript grava num arquivo temporário e a gente lê.
    /// O `is running` vem antes do `tell`: falar com um app fechado abriria o app.
    private static func doMusic() async -> NSImage? {
        let arquivo = FileManager.default.temporaryDirectory.appendingPathComponent("kizami-capa-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: arquivo) }
        let script = """
            if application "Music" is not running then return ""
            tell application "Music"
                if player state is not playing then return ""
                if (count of artworks of current track) is 0 then return ""
                set bytes to raw data of artwork 1 of current track
            end tell
            set destino to open for access (POSIX file "\(arquivo.path)") with write permission
            set eof destino to 0
            write bytes to destino
            close access destino
            return "ok"
            """
        guard await AppleScript.rodar(script) == "ok", let dados = try? Data(contentsOf: arquivo) else { return nil }
        return NSImage(data: dados)
    }

    /// O Spotify entrega o id da faixa e o endereço da capa no CDN dele. Se o id não é o da faixa anunciada,
    /// a resposta ainda é da faixa anterior e fica de fora.
    private static func doSpotify(faixa: String) async -> NSImage? {
        let script = """
            if application "Spotify" is not running then return ""
            tell application "Spotify" to return (id of current track) & linefeed & (artwork url of current track)
            """
        guard let resposta = await AppleScript.rodar(script)?.split(separator: "\n").map(String.init), resposta.count == 2,
              resposta[0] == faixa, let url = URL(string: resposta[1]), doCDN(url) else { return nil }
        var pedido = URLRequest(url: url)
        pedido.timeoutInterval = 10
        guard let (dados, http) = try? await URLSession.shared.data(for: pedido),
              (http as? HTTPURLResponse)?.statusCode == 200,
              http.url.map(doCDN) == true,  // um redirecionamento para fora do CDN não vale
              dados.count < 5_000_000 else { return nil }
        return NSImage(data: dados)
    }

    private static func doCDN(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host() else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co")
    }
}

/// Roda AppleScript pelo `osascript`, fora da thread principal: na primeira vez o macOS pergunta se o Kizami
/// pode controlar o player e espera a resposta da pessoa.
enum AppleScript {
    /// Tempo máximo de um pedido ao player. Folgado: na primeira vez ele espera a pessoa responder à permissão.
    private static let limite: Duration = .seconds(30)

    /// Com `limite`: um player travado não segura o pedido para sempre.
    static func rodar(_ script: String) async -> String? {
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        processo.arguments = ["-e", script]
        let saida = Pipe()
        processo.standardOutput = saida
        processo.standardError = FileHandle.nullDevice
        let resultado: String? = await withCheckedContinuation { continuacao in
            processo.terminationHandler = { fim in
                let texto = String(decoding: saida.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuacao.resume(returning: fim.terminationStatus == 0 ? texto.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
            }
            do {
                try processo.run()
            } catch {
                continuacao.resume(returning: nil)
                return
            }
            Task.detached {
                try? await Task.sleep(for: limite)
                if processo.isRunning { processo.terminate() }  // o terminationHandler devolve nil
            }
        }
        return resultado
    }
}
