import AppKit
import CoreAudio
import Observation

/// O que um player anunciou sobre a faixa atual.
struct Metadados: Equatable, Sendable {
    var titulo: String?
    var artista: String?
    var tocando: Bool
    /// Muda a cada faixa: é quando a capa é buscada de novo.
    var chave: String?
    /// O player parou de vez (Stopped), não só pausou: aí ele sai da ilha.
    var parado = false
}

/// Regras puras para descobrir quem está tocando som.
enum Som {
    static let music = "com.apple.Music"
    static let spotify = "com.spotify.client"
    /// Apps que tocam mídia. O Core Audio diz que a saída de áudio de um processo está aberta, não que algo audível
    /// está tocando: o Claude Desktop e o Kanji, por exemplo, mantêm a saída aberta em silêncio (visto no teste).
    /// Saber se há som de verdade pediria gravar o áudio do sistema (permissão de Gravação de Áudio).
    // ponytail: lista fechada de players e navegadores; um app de mídia que não está aqui não aparece na ilha.
    // Adicionar o bundle id dele, ou trocar por um tap de áudio se a lista virar manutenção.
    static let tocadores: Set<String> = [
        music, spotify, "com.apple.TV", "com.apple.podcasts", "com.apple.QuickTimePlayerX",
        "org.videolan.vlc", "com.colliderli.iina", "com.tidal.desktop", "com.amazon.music", "com.deezer.deezer-desktop",
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
        "com.brave.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "app.zen-browser.zen",
    ]

    /// Notificações que os próprios players publicam a cada troca de faixa, play ou pausa. Não pedem permissão.
    static let avisosDosPlayers: [(nome: String, app: String)] = [
        ("com.apple.Music.playerInfo", music),
        ("com.spotify.client.PlaybackStateChanged", spotify),
    ]

    /// O .app mais de fora no caminho do processo. Navegadores e apps Electron tocam som por processos auxiliares
    /// aninhados (".../Google Chrome.app/Contents/Frameworks/.../Google Chrome Helper.app/..."), e o app que
    /// importa é o de fora.
    static func caminhoDoApp(_ processo: String) -> String? {
        guard let fim = processo.range(of: ".app/") ?? (processo.hasSuffix(".app") ? processo.range(of: ".app") : nil) else {
            return nil
        }
        return String(processo[..<fim.lowerBound]) + ".app"
    }

    /// Quando o processo não está dentro de um .app: o som do Safari sai pelo processo de GPU do WebKit, no sistema.
    // ponytail: todo som do WebKit vira Safari; o Mail ou outro app WebKit tocando som apareceriam como Safari.
    static func appPorBundle(_ bundle: String) -> String? {
        bundle.hasPrefix("com.apple.WebKit") ? "com.apple.Safari" : nil
    }

    /// Lê o que o Music ou o Spotify mandam na notificação. Título e artista passam pela mesma limpeza das atividades:
    /// vêm de outro processo.
    static func metadados(_ info: [AnyHashable: Any]) -> Metadados {
        let titulo = (info["Name"] as? String).map { Atividade.limpo($0, ate: 80) }.flatMap { $0.isEmpty ? nil : $0 }
        let artista = (info["Artist"] as? String).map { Atividade.limpo($0, ate: 80) }.flatMap { $0.isEmpty ? nil : $0 }
        let id = info["PersistentID"].map { "\($0)" } ?? info["Track ID"] as? String
        let estado = info["Player State"] as? String
        return Metadados(titulo: titulo, artista: artista, tocando: estado == "Playing",
                         chave: id ?? titulo.map { "\($0)|\(artista ?? "")" }, parado: estado == "Stopped")
    }

    /// Quem a ilha mostra agora, e se está pausado.
    /// - `comSom`: o estabilizador diz que o último app está mandando som (2 s seguidos).
    /// - `ultimo`: o último app que tocou de verdade.
    /// - `anuncioRecente`: o player falou há menos de 3 s (um play que acabou de ser dado).
    /// Sem som, um player que dá para retomar pela ilha (Music, Spotify) continua nela, pausado, enquanto estiver
    /// aberto e não tiver parado de vez, mesmo sem ter chegado o aviso de pausa (visto: a música sumia ao pausar).
    static func mostrar(comSom: Bool, ultimo: String?, players: [String: Metadados], rodando: Bool,
                        anuncioRecente: Bool) -> (app: String, pausado: Bool)? {
        guard let ultimo else { return nil }
        let anunciado = players[ultimo]
        if comSom {
            return (ultimo, anunciado?.tocando == false)  // acabou de pausar: o som ainda não fechou, o player já disse
        }
        guard Controle.sabeControlar(ultimo), rodando, anunciado?.parado != true else { return nil }
        // Sem som, está pausado; a exceção é o play que acabou de ser dado (o som ainda não completou os 2 s).
        // Um "tocando" antigo não vale: o aviso da pausa pode não ter chegado.
        return (ultimo, !(anunciado?.tocando == true && anuncioRecente))
    }
}

/// Liga e desliga sem piscar: o som precisa durar `entrar` consultas seguidas para aparecer (um "plim" de
/// notificação não conta) e sumir por `sair` seguidas para ir embora (a pausa entre duas faixas não conta).
struct Estabilizador {
    static let entrar = 2
    static let sair = 3
    private(set) var ligado = false
    private var seguidos = 0

    mutating func registrar(_ tocando: Bool) -> Bool {
        seguidos = tocando == ligado ? 0 : seguidos + 1
        if seguidos >= (ligado ? Self.sair : Self.entrar) {
            ligado.toggle()
            seguidos = 0
        }
        return ligado
    }
}

/// Quem está tocando som no Mac agora, com título, artista e miniatura quando o player conta.
/// O Core Audio diz qual processo manda som para a saída (macOS 14.2+, sem permissão); o Music e o Spotify
/// dizem a faixa por notificação; a capa vem de `Capa`.
@MainActor @Observable
final class TocandoAgora {
    /// Bundle id do app que está tocando.
    private(set) var app: String?
    private(set) var nomeDoApp = ""
    private(set) var icone: NSImage?
    private(set) var metadados: Metadados?
    private(set) var capa: NSImage?
    /// Sem som, ou o player disse que pausou: a ilha mostra o botão de tocar e para as barras.
    private(set) var pausado = false

    @ObservationIgnored private var dosPlayers: [String: Metadados] = [:]
    @ObservationIgnored private var ultimoAnuncio: [String: Date] = [:]
    @ObservationIgnored private var estabilizador = Estabilizador()
    @ObservationIgnored private var ultimoApp: String?
    @ObservationIgnored private var capaPedida: String?
    @ObservationIgnored private var pausadoDesde: Date?
    /// Um player em pausa fica na ilha até este tempo, para dar play de novo pela ilha.
    private static let pausaMaxima: TimeInterval = 15 * 60

    func iniciar() {
        let centro = DistributedNotificationCenter.default()
        for (nome, app) in Som.avisosDosPlayers {
            centro.addObserver(forName: Notification.Name(nome), object: nil, queue: .main) { [weak self] aviso in
                let lidos = Som.metadados(aviso.userInfo ?? [:])
                MainActor.assumeIsolated { self?.receber(lidos, de: app) }
            }
        }
        // ponytail: consulta o Core Audio uma vez por segundo; trocar por listeners de
        // kAudioProcessPropertyIsRunningOutput se o segundo de atraso incomodar.
        Task { [weak self] in
            while !Task.isCancelled {
                // Fora da thread principal: o coreaudiod pode demorar a responder quando um dispositivo muda.
                let apps = await Task.detached { Self.appsTocando() }.value
                guard let self else { return }
                self.conferir(apps)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func receber(_ lidos: Metadados, de app: String) {
        dosPlayers[app] = lidos
        ultimoAnuncio[app] = .now
        registro.info("player: \(lidos.tocando ? "tocando" : lidos.parado ? "parado" : "pausado", privacy: .public)")
        guard app == self.app else { return }
        atualizar(app)
        pausado = !lidos.tocando  // na hora: o botão troca sem esperar a próxima consulta
    }

    private func conferir(_ tocando: [String]) {
        // O Spotify mantém a saída de áudio aberta um tempo depois da pausa: vale o que ele anunciou,
        // e um Spotify pausado não esconde o navegador que está tocando.
        let candidatos = tocando.filter { dosPlayers[$0]?.tocando != false }
        // Com dois tocando, vale o player que diz a faixa (um vídeo mudo no navegador não tira a música da ilha).
        let valendo = candidatos.first { dosPlayers[$0]?.tocando == true } ?? candidatos.first
        if let valendo { ultimoApp = valendo }
        let comSom = estabilizador.registrar(valendo != nil)
        let rodando = ultimoApp.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
        let recente = ultimoApp.flatMap { ultimoAnuncio[$0] }.map { Date.now.timeIntervalSince($0) < 3 } ?? false
        guard let (app, pausado) = Som.mostrar(comSom: comSom, ultimo: ultimoApp, players: dosPlayers, rodando: rodando,
                                               anuncioRecente: recente) else {
            if self.app != nil { limpar() }
            return
        }
        pausadoDesde = pausado ? (pausadoDesde ?? .now) : nil
        if Date.now.timeIntervalSince(pausadoDesde ?? .now) > Self.pausaMaxima {
            limpar()
            return
        }
        atualizar(app)
        if pausado != self.pausado { self.pausado = pausado }
    }

    private func atualizar(_ app: String) {
        if app != self.app {
            if self.app == nil { registro.info("som: começou") }
            self.app = app
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
            nomeDoApp = url.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
                ?? url?.deletingPathExtension().lastPathComponent ?? ""
            icone = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            capa = nil
            capaPedida = nil
        }
        let lidos = dosPlayers[app]
        if lidos != metadados { metadados = lidos }
        pedirCapa(app: app, chave: lidos?.chave)
    }

    /// Uma vez por faixa, e só dos players que sabem dar a capa.
    private func pedirCapa(app: String, chave: String?) {
        guard let chave, chave != capaPedida, Capa.sabeBuscar(app) else { return }
        capaPedida = chave
        capa = nil
        Task { [weak self] in
            let imagem = await Capa.buscar(app: app, faixa: chave)
            // A faixa pode ter mudado enquanto a capa chegava.
            guard let self, self.capaPedida == chave else { return }
            self.capa = imagem
        }
    }

    private func limpar() {
        registro.info("som: parou")
        pausadoDesde = nil
        ultimoApp = nil  // senão o player voltaria à ilha, pausado, só por ainda estar aberto
        pausado = false
        app = nil
        nomeDoApp = ""
        icone = nil
        metadados = nil
        capa = nil
        capaPedida = nil
    }

    /// Bundle ids dos apps cujos processos estão mandando som para a saída agora, sem repetir.
    nonisolated private static func appsTocando() -> [String] {
        let sistema = AudioObjectID(kAudioObjectSystemObject)
        var endereco = endereco(kAudioHardwarePropertyProcessObjectList)
        var tamanho: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sistema, &endereco, 0, nil, &tamanho) == noErr, tamanho > 0 else { return [] }
        var processos = [AudioObjectID](repeating: 0, count: Int(tamanho) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sistema, &endereco, 0, nil, &tamanho, &processos) == noErr else { return [] }

        var apps: [String] = []
        for processo in processos where ler(processo, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0 {
            let pid = ler(processo, kAudioProcessPropertyPID, pid_t(-1))
            guard let app = appDoProcesso(processo, pid: pid), Som.tocadores.contains(app), !apps.contains(app) else { continue }
            apps.append(app)
        }
        return apps
    }

    nonisolated private static func appDoProcesso(_ processo: AudioObjectID, pid: pid_t) -> String? {
        var caminho = [CChar](repeating: 0, count: 4096)
        if pid > 0, proc_pidpath(pid, &caminho, UInt32(caminho.count)) > 0,
           let app = Som.caminhoDoApp(String(decoding: caminho.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)),
           let bundle = Bundle(path: app)?.bundleIdentifier {
            return bundle
        }
        var endereco = endereco(kAudioProcessPropertyBundleID)
        var valor: Unmanaged<CFString>?
        var tamanho = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(processo, &endereco, 0, nil, &tamanho, &valor) == noErr,
              let bundle = valor?.takeRetainedValue() as String? else { return nil }
        return Som.appPorBundle(bundle)  // processo de linha de comando (afplay) fica de fora: não tem app para mostrar
    }

    nonisolated private static func ler<T: BitwiseCopyable>(_ objeto: AudioObjectID, _ seletor: AudioObjectPropertySelector, _ padrao: T) -> T {
        var endereco = endereco(seletor)
        var valor = padrao
        var tamanho = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(objeto, &endereco, 0, nil, &tamanho, &valor) == noErr ? valor : padrao
    }

    nonisolated private static func endereco(_ seletor: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: seletor, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
