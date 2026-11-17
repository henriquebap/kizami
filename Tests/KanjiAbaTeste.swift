import CoreGraphics
import Foundation

@MainActor func testarKanjiAba() {
    let json = { (texto: String) in Data(texto.utf8) }
    let padrao = TeclasDoKanji(keyCode: 2, carbon: 4096 | 2048, tecla: "D")!

    // Atalho gravado pelo Kanji → tecla virtual, flags do CGEvent e legenda.
    let ctrlOpt = TeclasDoKanji.decodificar(json(#"{"tecla":"K","keyCode":40,"modificadores":6144}"#), padrao: padrao, exigirCtrlOpt: true)
    conferir("kanji: keyCode", ctrlOpt.keyCode, 40)
    conferir("kanji: ⌃⌥ vira control + alternate", ctrlOpt.flags, [.maskControl, .maskAlternate])
    conferir("kanji: legenda ⌃⌥K", ctrlOpt.legenda, "⌃⌥K")
    let antigo = json(#"{"tecla":"D","keyCode":2,"modificadores":768}"#)
    let shiftCmd = TeclasDoKanji.decodificar(antigo, padrao: padrao, exigirCtrlOpt: false)
    conferir("kanji: ⇧⌘ vira shift + command", shiftCmd.flags, [.maskShift, .maskCommand])
    conferir("kanji: legenda na ordem dos menus", shiftCmd.legenda, "⇧⌘D")
    conferir("kanji: versão nova ignora atalho sem ⌃⌥", TeclasDoKanji.decodificar(antigo, padrao: padrao, exigirCtrlOpt: true), padrao)
    conferir("kanji: espaço vira ␣", TeclasDoKanji(keyCode: 49, carbon: 4096 | 2048, tecla: "Espaço")?.legenda, "⌃⌥␣")

    // Inválido → padrão.
    for (nome, texto) in [
        ("JSON quebrado", "{tecla"),
        ("sem campo", #"{"tecla":"D","keyCode":2}"#),
        ("keyCode fora da faixa", #"{"tecla":"D","keyCode":300,"modificadores":6144}"#),
        ("bit desconhecido", #"{"tecla":"D","keyCode":2,"modificadores":6145}"#),
        ("só shift", #"{"tecla":"D","keyCode":2,"modificadores":512}"#),
        ("tecla vazia", #"{"tecla":"","keyCode":2,"modificadores":6144}"#),
    ] {
        conferir("kanji: \(nome) → padrão", TeclasDoKanji.decodificar(json(texto), padrao: padrao, exigirCtrlOpt: false), padrao)
    }
    conferir("kanji: nada gravado → padrão", TeclasDoKanji.decodificar(nil, padrao: padrao, exigirCtrlOpt: false), padrao)

    // Ações: a versão antiga não tem transcrever e abre com ⌃⌥T; a nova, com ⌃⌥K.
    let antigas = AcaoKanji.lidas(nova: false) { _ in nil }
    conferir("kanji: ações da versão antiga", antigas.map(\.tipo), [.ditar, .abrir])
    conferir("kanji: abrir antigo", antigas.last?.teclas.legenda, "⌃⌥T")
    let novas = AcaoKanji.lidas(nova: true) { $0 == "atalho.1" ? json(#"{"tecla":"J","keyCode":38,"modificadores":6144}"#) : nil }
    conferir("kanji: ações da versão nova", novas.map(\.tipo), [.ditar, .transcrever, .abrir])
    conferir("kanji: legendas da versão nova", novas.map(\.teclas.legenda), ["⌃⌥J", "⌃⌥M", "⌃⌥K"])

    // Cabeçalho do SKILL.md.
    let campos = SkillDoKanji.cabecalho("---\nnome: Informal\ncor: Verde\natalho: 1\n---\nEscreva solto.\natalho: 9\nnome: Outra", inteiro: true)
    let informal = SkillDoKanji(id: "informal", campos: campos ?? [:])
    conferir("skill: nome", informal.nome, "Informal")
    conferir("skill: cor", informal.cor, "verde")
    conferir("skill: o corpo nunca entra", informal.tecla, "1")
    conferir("skill: legenda", informal.teclas?.legenda, "⇧⌘1")
    conferir("skill: tecla virtual", informal.teclas?.keyCode, 18)
    let claude = SkillDoKanji(id: "x", campos: SkillDoKanji.cabecalho("---\r\nname: Prompt\r\natalho: a\r\n---\r\n", inteiro: true) ?? [:])
    conferir("skill: name do Claude e \\r\\n", claude.nome, "Prompt")
    conferir("skill: atalho em minúscula", claude.teclas?.legenda, "⇧⌘A")
    let invalida = SkillDoKanji(id: "x", campos: SkillDoKanji.cabecalho("---\natalho: T\ncor: laranja\n---\n", inteiro: true) ?? [:])
    conferir("skill: tecla reservada fica sem atalho", invalida.tecla, nil)
    conferir("skill: cor fora da lista sai do id, como no Kanji", invalida.cor, SkillDoKanji.cores[120 % 6])
    conferir("skill: sem cabeçalho", SkillDoKanji.cabecalho("Só a instrução.\natalho: 1", inteiro: true), [:])
    conferir("skill: cabeçalho sem fechar não vale", SkillDoKanji.cabecalho("---\natalho: 1\n", inteiro: true), [:])
    conferir("skill: pedaço no meio do cabeçalho pede mais", SkillDoKanji.cabecalho("---\nnome: A\nat", inteiro: false), nil)
    conferir("skill: linha cortada não fecha", SkillDoKanji.cabecalho("---\nnome: A\n--", inteiro: false), nil)
    conferir("skill: fecha no pedaço", SkillDoKanji.cabecalho("---\nnome: A\n---\nco", inteiro: false), ["nome": "A"])
    conferir("skill: sem nome usa a pasta", SkillDoKanji(id: "pasta", campos: ["nome": ""]).nome, "pasta")

    // Leitura do arquivo: para no cabeçalho, mesmo com um corpo grande depois.
    let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("kizami-teste-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    let arquivo = pasta.appendingPathComponent("SKILL.md")
    try? Data(("---\nnome: Longa\natalho: 2\n---\n" + String(repeating: "corpo ", count: 10_000)).utf8).write(to: arquivo)
    conferir("skill: lida do arquivo", SkillDoKanji.ler(arquivo, id: "longa")?.teclas?.legenda, "⇧⌘2")
    try? Data(String(repeating: "x", count: 40_000).utf8).write(to: arquivo)
    conferir("skill: arquivo sem cabeçalho", SkillDoKanji.ler(arquivo, id: "x")?.tecla, nil)
    conferir("skill: arquivo que não existe", SkillDoKanji.ler(pasta.appendingPathComponent("nada"), id: "x"), nil)
    try? FileManager.default.removeItem(at: pasta)

    // Ordem e conflitos, como o Kanji registra.
    let acoes = AcaoKanji.lidas(nova: false) { $0 == "atalho.1" ? antigo : nil }  // ditar em ⇧⌘D
    let skills = SkillDoKanji.organizar([
        SkillDoKanji(id: "b", campos: ["nome": "Beta"]),
        SkillDoKanji(id: "d", campos: ["nome": "Dita", "atalho": "D"]),
        SkillDoKanji(id: "z", campos: ["nome": "Zeta", "atalho": "2"]),
        SkillDoKanji(id: "a", campos: ["nome": "Alfa", "atalho": "2"]),
        SkillDoKanji(id: "u", campos: ["nome": "Um", "atalho": "1"]),
    ], acoes: acoes)
    conferir("skills: ordem do Kanji", skills.map(\.nome), ["Um", "Alfa", "Zeta", "Dita", "Beta"])
    conferir("skills: repetida e igual à ação ficam sem atalho", skills.map(\.tecla), ["1", "2", nil, nil, nil])

    conferir("aba: altura sem skills", Geometria.alturaKanji(skills: 0), 62)
    conferir("aba: altura com skills", Geometria.alturaKanji(skills: 3), 112)
}
