import Foundation

// Regras puras do Kizami: geometria da ilha, comandos da linha de comando e validação do que chega de fora.
@MainActor var falhas = 0

@MainActor func conferir<T: Equatable>(_ nome: String, _ obtido: T, _ esperado: T) {
    let ok = obtido == esperado
    print(ok ? "ok   " : "FALHA", nome, ok ? "" : "\n  obtido:   \(obtido)\n  esperado: \(esperado)")
    if !ok { falhas += 1 }
}

@MainActor func testarGeometria() {
    // Medidas reais do MacBook 14" com macOS 27 (NSScreen.safeAreaInsets e auxiliaryTop*Area).
    let mac = Geometria(tela: CGRect(x: 0, y: 0, width: 1512, height: 982), esquerda: 663.5, direita: 663.5,
                        topoSeguro: 32, barraDeMenus: 24)
    conferir("notch do MacBook 14\"", mac.notch, CGSize(width: 185, height: 32))
    conferir("compacta centrada no notch", mac.retangulo(mac.compacta), CGRect(x: 621.5, y: 950, width: 269, height: 32))
    conferir("aviso: uma linha abaixo do notch", mac.retangulo(mac.aviso), CGRect(x: 606, y: 914, width: 300, height: 68))
    conferir("aberta com 1 linha é baixa", mac.aberta(linhas: 1), CGSize(width: 340, height: 84))
    conferir("aberta com 3 linhas", mac.aberta(linhas: 3), CGSize(width: 340, height: 152))
    conferir("aberta não passa de 3 linhas", mac.aberta(linhas: 8), mac.aberta(linhas: 3))
    conferir("só a bandeja, sem linhas", mac.aberta(linhas: 0, bandeja: true), CGSize(width: 340, height: 118))
    conferir("lista de 2 e bandeja", mac.aberta(linhas: 2, bandeja: true), CGSize(width: 340, height: 192))
    conferir("sem bandeja, 0 linhas vira 1", mac.aberta(linhas: 0), mac.aberta(linhas: 1))
    conferir("janela cabe a maior forma e a sombra", mac.janela, CGRect(x: 568, y: 738, width: 376, height: 244))
    conferir("cursor encostado no topo do notch abre", mac.gatilho.contains(CGPoint(x: 756, y: 982)), true)
    conferir("cursor na asa (barra de menus) não abre", mac.gatilho.contains(CGPoint(x: 650, y: 970)), false)
    conferir("aberta, a ilha inteira segura o hover", mac.zona(mac.aberta(linhas: 3)).contains(CGPoint(x: 600, y: 850)), true)

    // Monitor externo à esquerda: x negativo, sem notch e com a barra de menus oculta.
    let externo = Geometria(tela: CGRect(x: -1920, y: 0, width: 1920, height: 1080), esquerda: nil, direita: nil,
                            topoSeguro: 0, barraDeMenus: 24)
    conferir("sem notch", externo.temNotch, false)
    conferir("sem notch: só as asas, com a altura da barra", externo.retangulo(externo.compacta),
             CGRect(x: -1002, y: 1056, width: 84, height: 24))
    conferir("sem notch: as asas abrem", externo.gatilho.contains(CGPoint(x: -960, y: 1070)), true)
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
    conferir("a que chegou vira aviso", mural.novidade?.id, "5")
    mural.remover(id: "5")
    conferir("removida, o aviso some junto", mural.novidade == nil, true)
    mural.receber(Atividade(id: "z", titulo: "z", expira: 0))
    mural.limpar()
    conferir("limpar tira o aviso", mural.novidade == nil, true)
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
    conferir("vazia e sem arraste, invisível", bandeja.visivel, false)
    bandeja.arrastando = true
    conferir("arrastando, aparece para receber", bandeja.visivel, true)
}

@main struct Teste {
    @MainActor static func main() {
        testarGeometria()
        testarComando()
        testarValidacao()
        testarBandeja()
        if falhas > 0 { exit(1) }
    }
}
