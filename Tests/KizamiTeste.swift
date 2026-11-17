import Foundation

// Regras puras do Kizami: geometria da ilha, comandos da linha de comando e validação do que chega de fora.
@MainActor func testarGeometria() {
    // Medidas reais do MacBook 14" com macOS 27 (NSScreen.safeAreaInsets e auxiliaryTop*Area).
    let mac = Geometria(tela: CGRect(x: 0, y: 0, width: 1512, height: 982), esquerda: 663.5, direita: 663.5,
                        topoSeguro: 32, barraDeMenus: 24)
    conferir("notch do MacBook 14\"", mac.notch, CGSize(width: 185, height: 32))
    conferir("compacta centrada no notch", mac.retangulo(mac.compacta), CGRect(x: 621.5, y: 950, width: 269, height: 32))
    conferir("aviso: uma linha abaixo do notch", mac.retangulo(mac.aviso), CGRect(x: 606, y: 914, width: 300, height: 68))
    conferir("três avisos: três linhas", mac.aviso(linhas: 3), CGSize(width: 300, height: 32 + 3 * 30 + 2 * 4 + 6))
    conferir("avisos não passam de três linhas", mac.aviso(linhas: 9), mac.aviso(linhas: 3))
    conferir("três ícones alargam as duas asas", mac.compacta(icones: 3), CGSize(width: 269 + 4 * 22, height: 32))
    conferir("nenhum ícone conta como um", mac.compacta(icones: 0), mac.compacta)
    conferir("repouso: um pouco maior que o notch", mac.repouso, CGSize(width: 225, height: 32))
    func secoes(_ tocando: Bool, _ atividades: Int, _ arquivos: Int, _ arrastando: Bool = false) -> Secoes {
        Secoes(tocando: tocando, atividades: atividades, arquivos: arquivos, arrastando: arrastando)
    }
    conferir("aberta com 1 linha é baixa", mac.aberta(secoes(false, 1, 0)), CGSize(width: 340, height: 120))
    conferir("aberta com 3 linhas", mac.aberta(secoes(false, 3, 0)), CGSize(width: 340, height: 188))
    conferir("aberta não passa de 3 linhas", mac.aberta(secoes(false, 8, 0)), mac.aberta(secoes(false, 3, 0)))
    conferir("vazia, aberta oferece a bandeja", mac.aberta(secoes(false, 0, 0)), CGSize(width: 340, height: 154))
    conferir("lista de 2 e bandeja", mac.aberta(secoes(false, 2, 1)), CGSize(width: 340, height: 228))
    conferir("só tocando, sem bandeja vazia", mac.aberta(secoes(true, 0, 0)), CGSize(width: 340, height: 142))
    conferir("arrastando, a bandeja aparece mesmo tocando", secoes(true, 0, 0, true).bandeja, true)
    conferir("janela cabe tudo junto e a sombra", mac.janela, CGRect(x: 559.5, y: 398, width: 393, height: 584))
    conferir("hoje e 2 sessões, sem bandeja vazia",
             mac.aberta(Secoes(tocando: false, atividades: 0, arquivos: 0, arrastando: false, sessoes: 2, hoje: true)),
             CGSize(width: 340, height: 32 + 8 + 26 + 10 + 40 + 10 + 64 + 14))
    conferir("aba de atalhos: cabeçalho e a fileira", mac.abertaAtalhos, CGSize(width: 340, height: 32 + 8 + 26 + 10 + 62 + 14))
    conferir("sessões não passam de 3", Secoes(tocando: false, atividades: 0, arquivos: 0, arrastando: false, sessoes: 9).sessoes, 3)
    conferir("cursor encostado no topo do notch abre", mac.gatilho.contains(CGPoint(x: 756, y: 982)), true)
    conferir("cursor na asa (barra de menus) não abre", mac.gatilho.contains(CGPoint(x: 650, y: 970)), false)
    conferir("aberta, a ilha inteira segura o hover", mac.zona(mac.aberta(secoes(false, 3, 0))).contains(CGPoint(x: 600, y: 850)), true)

    // Tela cheia, com as janelas reais do fundo da mesa (MacBook 14" e um monitor de 1920x1080 à esquerda).
    let interno = CGRect(x: 0, y: 0, width: 1512, height: 982), lateral = CGRect(x: -1920, y: -98, width: 1920, height: 1080)
    conferir("mesa à vista: não é tela cheia", Geometria.emTelaCheia(tela: interno, fundos: [lateral, interno], mesa: true), false)
    conferir("o fundo saiu do monitor: tela cheia", Geometria.emTelaCheia(tela: interno, fundos: [lateral], mesa: true), true)
    conferir("tela cheia num monitor não esconde o outro", Geometria.emTelaCheia(tela: lateral, fundos: [lateral], mesa: true), false)
    conferir("MacBook sozinho em tela cheia: nenhum fundo à vista", Geometria.emTelaCheia(tela: interno, fundos: [], mesa: true), true)
    conferir("sem janelas de fundo no sistema não dá para saber: fica", Geometria.emTelaCheia(tela: interno, fundos: [], mesa: false), false)

    // Monitor externo à esquerda: x negativo, sem notch e com a barra de menus oculta.
    let externo = Geometria(tela: CGRect(x: -1920, y: 0, width: 1920, height: 1080), esquerda: nil, direita: nil,
                            topoSeguro: 0, barraDeMenus: 24)
    conferir("sem notch", externo.temNotch, false)
    conferir("sem notch: só as asas, com altura para a capa não encostar", externo.retangulo(externo.compacta),
             CGRect(x: -1030, y: 1050, width: 140, height: 30))
    conferir("sem notch: fechada não é mais estreita que o repouso", externo.compacta.width >= externo.repouso.width, true)
    conferir("sem notch: o conteúdo aberto começa no topo, sem faixa vazia", externo.aberta(secoes(true, 0, 0)).height, 4 + 8 + 26 + 10 + 52 + 14)
    conferir("com notch: o conteúdo começa abaixo da câmera", mac.faixaDoTopo, 32)
    conferir("sem notch: a pílula em repouso abre", externo.gatilho.contains(CGPoint(x: -1010, y: 1070)), true)
    conferir("áreas auxiliares sem topo seguro não contam como notch",
             Geometria(tela: externo.tela, esquerda: 10, direita: 10, topoSeguro: 0, barraDeMenus: 24).temNotch, false)
}

@MainActor func testarComando() {
    conferir("enviar com tudo", Comando.ler(["enviar", "--titulo", "Build pronto", "--simbolo", "hammer", "--id", "build",
                                             "--cor", "verde", "--expira", "5", "--detalhe", "12 s"]),
             .enviar(Atividade(id: "build", titulo: "Build pronto", detalhe: "12 s", simbolo: "hammer", cor: "verde", expira: 5)))
    conferir("enviar sem título", Comando.ler(["enviar", "--id", "x"]), nil)
    conferir("opção desconhecida não passa calada", Comando.ler(["enviar", "--titlo", "x"]), nil)
    conferir("opção sem valor", Comando.ler(["enviar", "--titulo"]), nil)
    conferir("expira que não é número", Comando.ler(["enviar", "--titulo", "x", "--expira", "já"]), nil)
    conferir("expira nan", Comando.ler(["enviar", "--titulo", "x", "--expira", "nan"]), nil)
    conferir("prioridade pela linha de comando",
             Comando.ler(["enviar", "--titulo", "x", "--id", "a", "--prioridade", "alta"]),
             .enviar(Atividade(id: "a", titulo: "x", prioridade: "alta")))
    conferir("ajuda não abre o app", Comando.ler(["--help"]), nil)
    conferir("remover", Comando.ler(["remover", "--id", "build"]), .remover("build"))
    conferir("remover sem id", Comando.ler(["remover"]), nil)
    conferir("limpar", Comando.ler(["limpar"]), .limpar)
    conferir("ação desconhecida", Comando.ler(["apagar"]), nil)
}

@MainActor func testarValidacao() {
    let base = Atividade(id: "a", titulo: "Título")
    conferir("título só com espaço é descartado", Atividade.validar(Atividade(id: "a", titulo: "   ")), nil)
    conferir("id vazio é descartado", Atividade.validar(Atividade(id: "", titulo: "x")), nil)
    conferir("título longo é cortado", Atividade.validar(Atividade(id: "a", titulo: String(repeating: "á", count: 200)))?.titulo.count, 60)
    conferir("símbolo inexistente vira o padrão", Atividade.validar(Atividade(id: "a", titulo: "x", simbolo: "nao.existe"))?.simbolo, "bell.fill")
    conferir("símbolo válido fica", Atividade.validar(Atividade(id: "a", titulo: "x", simbolo: "hammer"))?.simbolo, "hammer")
    conferir("cor fora da lista some", Atividade.validar(Atividade(id: "a", titulo: "x", cor: "#ff0000"))?.cor, nil as String?)
    conferir("expira sem valor ganha o padrão", Atividade.validar(base)?.expira, Atividade.expiraPadrao)
    conferir("expira é limitado a uma hora", Atividade.validar(Atividade(id: "a", titulo: "x", expira: 99_999))?.expira, 3600)
    conferir("expira negativo vira 0 (fica até remover)", Atividade.validar(Atividade(id: "a", titulo: "x", expira: -5))?.expira, 0)
    conferir("expira NaN ganha o padrão", Atividade.validar(Atividade(id: "a", titulo: "x", expira: .nan))?.expira, Atividade.expiraPadrao)

    // Texto vindo de qualquer processo do Mac.
    conferir("título só de largura zero é descartado", Atividade.validar(Atividade(id: "a", titulo: "\u{200B}\u{2060} \u{200B}")), nil)
    conferir("caractere de direção some", Atividade.validar(Atividade(id: "a", titulo: "abc\u{202E}def"))?.titulo, "abcdef")
    conferir("quebra de linha some do título", Atividade.validar(Atividade(id: "a", titulo: "um\ndois"))?.titulo, "umdois")
    let zalgo = "a" + String(repeating: "\u{0301}", count: 5000)
    conferir("Zalgo é cortado por escalares", (Atividade.validar(Atividade(id: "a", titulo: zalgo))?.titulo.unicodeScalars.count ?? 0) <= 240, true)
    conferir("emoji com ZWJ fica inteiro", Atividade.validar(Atividade(id: "a", titulo: "👩‍💻 pronto"))?.titulo, "👩‍💻 pronto")
    conferir("detalhe só com espaço some", Atividade.validar(Atividade(id: "a", titulo: "x", detalhe: "  "))?.detalhe, nil as String?)

    let mural = Mural()
    for i in 0..<10 { mural.receber(Atividade(id: "\(i)", titulo: "t\(i)", expira: 0)) }
    conferir("mural guarda no máximo 8", mural.atividades.count, Mural.maximo)
    conferir("mais recente primeiro", mural.atividades.first?.id, "9")
    mural.receber(Atividade(id: "5", titulo: "de novo", expira: 0))
    conferir("mesmo id substitui e sobe", mural.atividades.map(\.id).prefix(2), ["5", "9"])
    conferir("sem duplicata", mural.atividades.filter { $0.id == "5" }.count, 1)
    conferir("a que chegou vira aviso", mural.avisos.first?.id, "5")
    mural.remover(id: "5")
    conferir("removida, sai da pilha de avisos", mural.avisos.contains { $0.id == "5" }, false)
    mural.receber(Atividade(id: "z", titulo: "z", expira: 0))
    mural.limpar()
    conferir("limpar tira o aviso", mural.avisos.isEmpty, true)

    // Prioridade: a fila da ilha.
    conferir("prioridade desconhecida vira normal", Atividade.validar(Atividade(id: "a", titulo: "x", prioridade: "máxima"))?.peso, 1)
    conferir("urgente pesa 3", Atividade(id: "a", titulo: "x", prioridade: "urgente").peso, 3)
    let fila = Mural()
    fila.receber(Atividade(id: "claude", titulo: "precisa de você", expira: 0, prioridade: "urgente"))
    for i in 0..<10 { fila.receber(Atividade(id: "n\(i)", titulo: "n", expira: 0)) }
    conferir("urgente fica na frente das mais novas", fila.atividades.first?.id, "claude")
    conferir("ilha cheia não derruba a urgente", fila.atividades.count == Mural.maximo && fila.atividades.contains { $0.id == "claude" }, true)
    conferir("as asas mostram até três", fila.destaques.map(\.id), ["claude", "n9", "n8"])
    conferir("a pilha de avisos tem até três, a urgente primeiro", fila.avisos.map(\.id), ["claude", "n9", "n8"])
    fila.limpar()
    fila.receber(Atividade(id: "silencio", titulo: "baixa", expira: 0, prioridade: "baixa"))
    conferir("baixa entra sem descer como aviso", [fila.atividades.count, fila.avisos.count], [1, 0])
    fila.receber(Atividade(id: "alta", titulo: "alta", expira: 0, prioridade: "alta"))
    fila.receber(Atividade(id: "normal", titulo: "normal", expira: 0))
    conferir("na pilha, a alta vem antes da normal mais nova", fila.avisos.map(\.id), ["alta", "normal"])
}

@MainActor func testarBandeja() {
    let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("kizami-teste-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: pasta) }
    let a = pasta.appendingPathComponent("a.txt"), b = pasta.appendingPathComponent("b.pdf")
    FileManager.default.createFile(atPath: a.path, contents: Data())
    FileManager.default.createFile(atPath: b.path, contents: Data())

    let bandeja = Bandeja()
    conferir("link da web não entra", bandeja.adicionar([URL(string: "https://exemplo.com/x")!]), 0)
    conferir("conta só os arquivos", bandeja.adicionar([a, b, a, URL(string: "https://exemplo.com/x")!]), 2)
    conferir("só arquivos, sem duplicata, na ordem", bandeja.arquivos.map(\.lastPathComponent), ["a.txt", "b.pdf"])
    bandeja.adicionar([a])
    conferir("soltar de novo leva para o fim", bandeja.arquivos.map(\.lastPathComponent), ["b.pdf", "a.txt"])
    bandeja.adicionar((0..<30).map { pasta.appendingPathComponent("\($0)") })
    conferir("no máximo 20, sai o mais antigo", bandeja.arquivos.count, Bandeja.maximo)
    conferir("o mais antigo saiu", bandeja.arquivos.contains(b), false)
    bandeja.podar()
    conferir("podar tira o que não existe mais", bandeja.arquivos.map(\.lastPathComponent), [] as [String])
    bandeja.adicionar([b])
    bandeja.remover(b)
    conferir("remover", bandeja.arquivos.isEmpty, true)
}

@MainActor func testarSom() {
    conferir("app de fora de um processo auxiliar",
             Som.caminhoDoApp("/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"),
             "/Applications/Google Chrome.app")
    conferir("app comum", Som.caminhoDoApp("/Applications/Spotify.app/Contents/MacOS/Spotify"), "/Applications/Spotify.app")
    conferir("linha de comando não tem app", Som.caminhoDoApp("/usr/bin/afplay"), nil)
    conferir("som do WebKit é o Safari", Som.appPorBundle("com.apple.WebKit.GPU"), "com.apple.Safari")
    conferir("outro bundle sem app", Som.appPorBundle("com.apple.audio.SystemSoundServer"), nil)
    conferir("player conta", Som.tocadores.contains("com.spotify.client"), true)
    conferir("navegador conta", Som.tocadores.contains("com.google.Chrome"), true)
    conferir("app que segura a saída em silêncio não conta", Som.tocadores.contains("com.anthropic.claudefordesktop"), false)
    conferir("o Kanji não conta", Som.tocadores.contains("io.github.henriquebap.kanji"), false)

    let music = Som.metadados(["Name": "Águas de Março", "Artist": "Elis\u{202E} Regina", "Player State": "Playing", "PersistentID": 42])
    conferir("Music: título", music.titulo, "Águas de Março")
    conferir("Music: artista limpo como texto de fora", music.artista, "Elis Regina")
    conferir("Music: tocando", music.tocando, true)
    conferir("Music: chave pelo PersistentID", music.chave, "42")
    let spotify = Som.metadados(["Name": "Song", "Player State": "Paused", "Track ID": "spotify:track:abc"])
    conferir("Spotify pausado não está tocando", spotify.tocando, false)
    conferir("pausado não é parado", spotify.parado, false)
    conferir("Stopped é parado", Som.metadados(["Player State": "Stopped"]).parado, true)

    // Quem a ilha mostra. O caso que sumia: pausou e o aviso de pausa não chegou.
    let playerTocando = [Som.spotify: Metadados(titulo: "x", artista: nil, tocando: true, chave: "1")]
    let playerPausado = [Som.spotify: Metadados(titulo: "x", artista: nil, tocando: false, chave: "1")]
    let playerParado = [Som.spotify: Metadados(titulo: "x", artista: nil, tocando: false, chave: "1", parado: true)]
    func mostrar(_ comSom: Bool, _ ultimo: String?, _ players: [String: Metadados], rodando: Bool = true, recente: Bool = false) -> String {
        Som.mostrar(comSom: comSom, ultimo: ultimo, players: players, rodando: rodando, anuncioRecente: recente).map { "\($0.app) \($0.pausado ? "pausado" : "tocando")" } ?? "nada"
    }
    conferir("com som, tocando", mostrar(true, Som.spotify, playerTocando), "com.spotify.client tocando")
    conferir("acabou de pausar, o som ainda não fechou", mostrar(true, Som.spotify, playerPausado), "com.spotify.client pausado")
    conferir("pausado fica na ilha", mostrar(false, Som.spotify, playerPausado), "com.spotify.client pausado")
    conferir("pausado sem aviso do player também fica", mostrar(false, Som.spotify, [:]), "com.spotify.client pausado")
    conferir("sem som e com um tocando antigo (a pausa se perdeu): pausado", mostrar(false, Som.spotify, playerTocando), "com.spotify.client pausado")
    conferir("acabou de dar play: tocando antes do som completar 2 s", mostrar(false, Som.spotify, playerTocando, recente: true), "com.spotify.client tocando")
    conferir("parado de vez sai", mostrar(false, Som.spotify, playerParado), "nada")
    conferir("player fechado sai", mostrar(false, Som.spotify, playerPausado, rodando: false), "nada")
    conferir("navegador sem som sai (não dá para retomar pela ilha)", mostrar(false, "com.google.Chrome", [:]), "nada")
    conferir("nada tocou ainda", mostrar(false, nil, [:]), "nada")
    conferir("Spotify: chave pelo Track ID", spotify.chave, "spotify:track:abc")
    conferir("sem nada", Som.metadados([:]), Metadados(titulo: nil, artista: nil, tocando: false, chave: nil))

    conferir("comando do Music", Controle.script(.alternar, app: Som.music),
             #"if application "Music" is running then tell application "Music" to playpause"#)
    conferir("comando do Spotify", Controle.script(.proxima, app: Som.spotify),
             #"if application "Spotify" is running then tell application "Spotify" to next track"#)
    conferir("navegador não tem comando", Controle.script(.alternar, app: "com.google.Chrome"), nil)

    var e = Estabilizador()
    conferir("um plim não liga", e.registrar(true), false)
    conferir("dois segundos de som ligam", e.registrar(true), true)
    conferir("um segundo de silêncio não desliga", e.registrar(false), true)
    _ = e.registrar(true)
    _ = e.registrar(false); _ = e.registrar(false)
    conferir("três de silêncio desligam", e.registrar(false), false)
}

@main struct Teste {
    @MainActor static func main() {
        testarGeometria()
        testarComando()
        testarValidacao()
        testarBandeja()
        testarSom()
        testarAgenda()
        testarTempo()
        testarClaude()
        testarMac()
        testarInteresses()
        testarKanjiAba()
        testarPlacar()
        testarCronometro()
        testarCopiados()
        testarEspelho()
        testarDownloads()
        testarGitHub()
        if falhas > 0 { exit(1) }
    }
}
