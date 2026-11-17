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
    typealias E = Painel.Entrada
    let calmo = Painel(E())
    conferir("dia calmo: só o cartão do dia", calmo.fileiras, [.larga(.dia(eventos: 0))])
    conferir("dia calmo: altura do cartão", mac.aberta(calmo), CGSize(width: 420, height: 32 + 8 + 26 + 10 + Painel.alturaDia(eventos: 0) + 14))
    conferir("dia com 5 eventos lista só 3", Painel(E(eventosHoje: 5)).fileiras, [.larga(.dia(eventos: 3))])
    conferir("música em destaque, o resto aos pares",
             Painel(E(sessoes: 2, tocando: true, tempo: true, agenda: true, mac: true)).fileiras,
             [.larga(.musica), .dupla(.tempo, .agenda), .dupla(.sessoes, .mac)])
    conferir("Claude precisa de você vence a música, e as sessões não repetem num widget",
             Painel(E(precisaDeVoce: true, sessoes: 3, tocando: true)).fileiras, [.larga(.claude(outras: true)), .sozinha(.musica)])
    conferir("reunião em destaque esconde o widget da agenda",
             Painel(E(reuniao: true, tempo: true, agenda: true)).fileiras, [.larga(.reuniao(link: false)), .sozinha(.tempo)])
    conferir("reunião sem link: sem a linha do botão", Painel.altura(.reuniao(link: false)) < Painel.altura(.reuniao(link: true)), true)
    conferir("no dia calmo, tempo e agenda estão no cartão do dia",
             Painel(E(tempo: true, agenda: true, mac: true)).fileiras, [.larga(.dia(eventos: 0)), .sozinha(.mac)])
    conferir("avisos logo depois do destaque, até 3",
             Painel(E(tocando: true, atividades: 7)).fileiras, [.larga(.musica), .larga(.atividades(3))])
    conferir("no máximo 6 widgets",
             Painel(E(sessoes: 1, reuniao: true, tocando: true, timer: true, tempo: true, agenda: true, lembretes: 2,
                      interesse: true, mac: true)).fileiras.count, 1 + 3)
    conferir("Hoje escondido e nada acontecendo: sem destaque", Painel(E(hoje: false, mac: true)).fileiras, [.sozinha(.mac)])
    conferir("bandeja no fim", Painel(E(hoje: false, bandeja: true)).fileiras, [.larga(.bandeja)])
    conferir("altura: destaque, dupla e o espaço entre eles",
             Painel(E(tocando: true, tempo: true, agenda: true)).altura, 84 + 8 + Painel.alturaWidget)
    conferir("janela cabe o Início mais alto e a sombra",
             mac.janela.height - Geometria.sombra >= mac.aberta(Painel.maior).height, true)
    conferir("aba de atalhos: cabeçalho e a fileira", mac.abertaAtalhos, CGSize(width: 420, height: 32 + 8 + 26 + 10 + 62 + 14))
    conferir("cursor encostado no topo do notch abre", mac.gatilho.contains(CGPoint(x: 756, y: 982)), true)
    conferir("cursor na asa (barra de menus) não abre", mac.gatilho.contains(CGPoint(x: 650, y: 970)), false)
    conferir("aberta, a ilha inteira segura o hover", mac.zona(mac.aberta(Painel(E(atividades: 3)))).contains(CGPoint(x: 600, y: 850)), true)

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
    conferir("sem notch: o conteúdo aberto começa no topo, sem faixa vazia", externo.aberta(Painel(E(tocando: true))).height, 4 + 8 + 26 + 10 + 84 + 14)
    conferir("com notch: o conteúdo começa abaixo da câmera", mac.faixaDoTopo, 32)
    conferir("sem notch: a pílula em repouso abre", externo.gatilho.contains(CGPoint(x: -1010, y: 1070)), true)
    conferir("agenda expandida: semana sem eventos", Geometria.alturaAgenda(semanas: 1, eventos: 0), 10 + 24 + 8 + 40 + 8 + 30 + 10)
    conferir("agenda expandida: mês de 6 semanas, lista cortada em 5 linhas", Geometria.alturaAgenda(semanas: 6, eventos: 9),
             10 + 24 + 8 + 14 + 6 * 24 + 8 + Geometria.alturaLinhas(5) + 10)
    conferir("música expandida com e sem a barra", [Geometria.alturaMusica(barra: true), Geometria.alturaMusica(barra: false)],
             [140, 108])
    conferir("a janela cabe o mês expandido",
             mac.janela.height - Geometria.sombra >= mac.abertaComAba(Geometria.alturaAgenda(semanas: 6, eventos: 9)).height, true)
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

    // A alta ou urgente manda nas asas só nos primeiros 2 min (v0.15).
    conferir("a alta que acabou de chegar manda nas asas", fila.importante, true)
    fila.remover(id: "alta")
    conferir("tirada a alta, as asas voltam à ordem", fila.importante, false)
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    func chegou(_ id: String, _ prioridade: String?, _ chegada: Date) -> Atividade {
        var a = Atividade(id: id, titulo: id, expira: 0, prioridade: prioridade)
        a.chegada = chegada
        return a
    }
    let urgente = chegou("u", "urgente", t0)
    conferir("janela da urgente: 2 min depois da chegada", Mural.importanteAte([urgente]), t0 + 120)
    conferir("com 1 min, ainda manda", Mural.importanteAte([urgente]).map { $0 > t0 + 60 }, true)
    conferir("com 2 min, já não manda", Mural.importanteAte([urgente]).map { $0 > t0 + 120 }, false)
    conferir("normal e baixa nunca mandam", Mural.importanteAte([chegou("n", nil, t0), chegou("b", "baixa", t0)]), nil)
    conferir("vale a janela da mais recente", Mural.importanteAte([urgente, chegou("a", "alta", t0 + 90)]), t0 + 210)
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

    testarProgresso()
    testarDestaque()

    var e = Estabilizador()
    conferir("um plim não liga", e.registrar(true), false)
    conferir("dois segundos de som ligam", e.registrar(true), true)
    conferir("um segundo de silêncio não desliga", e.registrar(false), true)
    _ = e.registrar(true)
    _ = e.registrar(false); _ = e.registrar(false)
    conferir("três de silêncio desligam", e.registrar(false), false)
}

/// A música expandida: a resposta do player, a unidade da duração do Spotify, o relógio local e o pulo na barra.
@MainActor func testarProgresso() {
    let t = Date(timeIntervalSince1970: 1_800_000_000)
    conferir("Spotify: duração em ms", Progresso.ler("83500\n215000\ntrue", app: Som.spotify, agora: t),
             Progresso(posicao: 83.5, duracao: 215, tocando: true, lidoEm: t))
    conferir("Spotify: se um dia vier em segundos", Progresso.ler("83500\n215\ntrue", app: Som.spotify, agora: t)?.duracao, 215)
    conferir("Spotify: em segundos e passado do que seria ms", Progresso.duracaoDoSpotify(3000, posicao: 600), 3000)
    conferir("Spotify: em ms no começo da faixa", Progresso.duracaoDoSpotify(3000, posicao: 0), 3)
    conferir("Music: duração mandada em ms pelo script", Progresso.ler("1000\n200500\nfalse", app: Som.music, agora: t),
             Progresso(posicao: 1, duracao: 200.5, tocando: false, lidoEm: t))
    conferir("resposta vazia (player fechado)", Progresso.ler("", app: Som.music, agora: t), nil)
    conferir("resposta torta", Progresso.ler("1,5\n200\ntrue", app: Som.music, agora: t), nil)
    conferir("sem duração", Progresso.ler("0\n0\ntrue", app: Som.music, agora: t), nil)
    conferir("posição além do fim fica no fim", Progresso.ler("300000\n200000\ntrue", app: Som.music, agora: t)?.posicao, 200)

    let p = Progresso(posicao: 10, duracao: 100, tocando: true, lidoEm: t)
    conferir("tocando, o relógio anda", p.posicao(em: t.addingTimeInterval(5)), 15)
    conferir("não passa do fim", p.posicao(em: t.addingTimeInterval(500)), 100)
    conferir("pausado, fica", Progresso(posicao: 10, duracao: 100, tocando: false, lidoEm: t).posicao(em: t.addingTimeInterval(5)), 10)
    conferir("leitura que confirma o relógio não troca",
             p.difere(de: Progresso(posicao: 15.4, duracao: 100, tocando: true, lidoEm: t.addingTimeInterval(5))), false)
    conferir("pulou na faixa troca", p.difere(de: Progresso(posicao: 40, duracao: 100, tocando: true, lidoEm: t.addingTimeInterval(5))), true)
    conferir("pausou troca", p.difere(de: Progresso(posicao: 15, duracao: 100, tocando: false, lidoEm: t.addingTimeInterval(5))), true)
    conferir("outra faixa troca", p.difere(de: Progresso(posicao: 15, duracao: 180, tocando: true, lidoEm: t.addingTimeInterval(5))), true)
    conferir("tempo: minutos", Progresso.tempo(65.9), "1:05")
    conferir("tempo: horas", Progresso.tempo(3725), "1:02:05")
    conferir("tempo: nunca negativo", Progresso.tempo(-3), "0:00")

    conferir("pular: inteiro dentro da faixa", Controle.scriptParaIr(app: Som.spotify, segundos: 83.7, duracao: 215),
             #"if application "Spotify" is running then tell application "Spotify" to set player position to 83"#)
    conferir("pular: além do fim vai ao fim", Controle.scriptParaIr(app: Som.music, segundos: 999, duracao: 215)?.hasSuffix(" to 215"), true)
    conferir("pular: antes do começo vai ao zero", Controle.scriptParaIr(app: Som.music, segundos: -4, duracao: 215)?.hasSuffix(" to 0"), true)
    conferir("pular: número inválido não vira script", Controle.scriptParaIr(app: Som.music, segundos: .nan, duracao: 215), nil)
    conferir("pular: navegador não", Controle.scriptParaIr(app: "com.google.Chrome", segundos: 1, duracao: 215), nil)
    conferir("posição: navegador não tem script", Controle.scriptDaPosicao(app: "com.google.Chrome"), nil)
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
        testarPersonalizacao()
        testarAtalhosApple()
        testarLembretes()
        testarFones()
        if falhas > 0 { exit(1) }
    }
}
