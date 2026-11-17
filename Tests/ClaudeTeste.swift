import Foundation

// Sessões do Claude Code: o JSON dos hooks (formato de https://code.claude.com/docs/en/hooks), a validação do que
// chega pela notificação, a ordem, a expiração e os avisos no mural.
@MainActor func testarClaude() {
    let uuid = "00893aaf-19fa-41d2-8238-13269b9b3ca0"
    func hook(_ evento: String, _ extra: String = "") -> Data {
        Data("""
            {"session_id":"\(uuid)","transcript_path":"/Users/x/.claude/projects/p/\(uuid).jsonl",
             "cwd":"/Users/x/Projetos/Kizami","permission_mode":"default","hook_event_name":"\(evento)"\(extra)}
            """.utf8)
    }
    func evento(_ dados: Data) -> MensagemClaude.Evento? { MensagemClaude.doHook(dados, app: "com.apple.Terminal")?.evento }

    let inicio = MensagemClaude.doHook(hook("SessionStart", #","source":"startup","model":"claude-opus-5""#), app: "com.apple.Terminal")
    conferir("SessionStart: id, pasta e app", inicio,
             MensagemClaude(id: uuid, pasta: "Kizami", evento: .inicio, app: "com.apple.Terminal"))
    conferir("UserPromptSubmit trabalha", evento(hook("UserPromptSubmit", #","prompt":"segredo""#)), .trabalhando)
    conferir("PreToolUse trabalha", evento(hook("PreToolUse", #","tool_name":"Bash","tool_input":{"command":"ls"}"#)), .trabalhando)
    conferir("PostToolUse trabalha", evento(hook("PostToolUse", #","tool_name":"Read","tool_response":{}"#)), .trabalhando)
    conferir("ferramenta de subagente é outro evento",
             evento(hook("PreToolUse", #","agent_id":"agent-abc123","agent_type":"Explore","tool_name":"Grep""#)), .subagente)
    conferir("permission_prompt precisa de você",
             evento(hook("Notification", #","message":"Claude needs your permission","title":"Permission needed","notification_type":"permission_prompt""#)),
             .precisaDeVoce)
    conferir("elicitation_dialog precisa de você", evento(hook("Notification", #","notification_type":"elicitation_dialog""#)), .precisaDeVoce)
    conferir("idle_prompt é pronta", evento(hook("Notification", #","message":"Claude is waiting","notification_type":"idle_prompt""#)), .pronta)
    conferir("auth_success ignorada", evento(hook("Notification", #","notification_type":"auth_success""#)), nil)
    conferir("Notification sem tipo ignorada", evento(hook("Notification", #","message":"oi""#)), nil)
    conferir("Stop é pronta", evento(hook("Stop", #","stop_hook_active":false,"last_assistant_message":"feito""#)), .pronta)
    conferir("SessionEnd encerra", evento(hook("SessionEnd", #","reason":"prompt_input_exit""#)), .fim)
    conferir("evento desconhecido ignorado", evento(hook("PreCompact")), nil)
    conferir("SubagentStop ignorado", evento(hook("SubagentStop", #","agent_id":"agent-abc123""#)), nil)
    conferir("lixo recusado", evento(Data("não é json".utf8)), nil)
    conferir("JSON sem session_id recusado", evento(Data(#"{"cwd":"/x","hook_event_name":"Stop"}"#.utf8)), nil)
    conferir("JSON que não é objeto recusado", evento(Data("[1,2]".utf8)), nil)
    let enorme = Data(#"{"session_id":"a","cwd":"/x","hook_event_name":"Stop","last_assistant_message":""#.utf8)
        + Data(repeating: 0x61, count: MensagemClaude.limiteHook) + Data(#""}"#.utf8)
    conferir("entrada acima do limite recusada", evento(enorme), nil)
    conferir("Stop com resposta longa (200 KB) passa",
             evento(hook("Stop", #","last_assistant_message":""# + String(repeating: "a", count: 200_000) + "\"")), .pronta)
    conferir("o prompt nunca entra na mensagem",
             MensagemClaude.doHook(hook("UserPromptSubmit", #","prompt":"segredo""#), app: nil)
                .flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self).contains("segredo") },
             false)

    // Validação do que chega pela notificação: qualquer processo pode postar.
    func texto(_ m: MensagemClaude) -> String { String(decoding: try! JSONEncoder().encode(m), as: UTF8.self) }
    conferir("mensagem boa passa", MensagemClaude.ler(texto(MensagemClaude(id: uuid, pasta: "Kizami", evento: .pronta, app: nil)))?.pasta, "Kizami")
    conferir("evento desconhecido recusado", MensagemClaude.ler(#"{"id":"a","pasta":"p","evento":"explodir"}"#), nil)
    conferir("id longo recusado (não cortado)", MensagemClaude.ler(texto(MensagemClaude(id: String(repeating: "a", count: 49), pasta: "p", evento: .pronta))), nil)
    conferir("id com caractere estranho recusado", MensagemClaude.ler(texto(MensagemClaude(id: "a/b", pasta: "p", evento: .pronta))), nil)
    conferir("pasta vazia recusada", MensagemClaude.ler(texto(MensagemClaude(id: "a", pasta: "\u{202E}  ", evento: .pronta))), nil)
    conferir("pasta cortada e limpa", MensagemClaude.ler(texto(MensagemClaude(id: "a", pasta: "\u{202E}" + String(repeating: "x", count: 99), evento: .pronta)))?.pasta,
             String(repeating: "x", count: 40))
    conferir("bundle id inválido vira nil", MensagemClaude.ler(texto(MensagemClaude(id: "a", pasta: "p", evento: .pronta, app: "com.x; rm -rf")))?.app, String?.none)
    conferir("tty do hook atravessa", MensagemClaude.doHook(hook("Stop"), app: AbaDoTerminal.terminal, tty: "ttys003")?.tty, "ttys003")
    conferir("tty bom passa", MensagemClaude.ler(texto(MensagemClaude(id: "a", pasta: "p", evento: .pronta, tty: "ttys003")))?.tty, "ttys003")
    for ruim in ["ttys", "ttys12345", "/dev/ttys003", "ttys003\" & do shell script \"x", "ttys٣", "tty.usb0", "console", ""] {
        let lida = MensagemClaude.ler(texto(MensagemClaude(id: "a", pasta: "p", evento: .pronta, tty: ruim)))
        conferir("tty inválido vira nil, a mensagem fica (\(ruim.count))", lida.map { $0.tty == nil }, true)
    }
    conferir("mensagem sem tty (versão antiga) passa", MensagemClaude.ler(#"{"id":"a","pasta":"p","evento":"pronta"}"#)?.tty, String?.none)
    conferir("mensagem acima de 4 KB recusada",
             MensagemClaude.ler(#"{"id":"a","evento":"pronta","pasta":""# + String(repeating: "x", count: 4100) + "\"}"), nil)
    conferir("sem objeto recusada", MensagemClaude.ler(nil), nil)

    // Regras da lista.
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    func m(_ id: String, _ evento: MensagemClaude.Evento, app: String? = nil) -> MensagemClaude {
        MensagemClaude(id: id, pasta: "pasta-\(id)", evento: evento, app: app)
    }
    var lista = SessaoClaude.aplicar(m("a", .inicio, app: "com.apple.Terminal"), a: [], agora: t0)
    conferir("SessionStart cria pronta", lista.map(\.estado), [.pronta])
    lista = SessaoClaude.aplicar(m("a", .trabalhando), a: lista, agora: t0 + 10)
    lista = SessaoClaude.aplicar(m("a", .trabalhando), a: lista, agora: t0 + 20)
    conferir("evento repetido não zera o tempo do estado", lista.first?.desde, t0 + 10)
    conferir("evento repetido atualiza o visto", lista.first?.visto, t0 + 20)
    conferir("app guardado quando o evento não traz", lista.first?.app, "com.apple.Terminal")
    lista = SessaoClaude.aplicar(m("a", .inicio), a: lista, agora: t0 + 30)
    conferir("SessionStart no meio (compactação) não muda o estado", lista.first?.estado, .trabalhando)
    var comTty = m("a", .pronta, app: AbaDoTerminal.terminal)
    comTty.tty = "ttys003"
    var pares = SessaoClaude.aplicar(comTty, a: lista, agora: t0 + 31)
    pares = SessaoClaude.aplicar(m("a", .pronta), a: pares, agora: t0 + 32)
    conferir("evento sem app guarda o app e o tty", pares.first.map { "\($0.app ?? "") \($0.tty ?? "")" }, "com.apple.Terminal ttys003")
    pares = SessaoClaude.aplicar(m("a", .pronta, app: "com.microsoft.VSCode"), a: pares, agora: t0 + 33)
    conferir("app novo sem tty não herda o tty antigo", pares.first?.tty, String?.none)

    // O AppleScript da aba: só Terminal e iTerm2, e o único texto de fora é o tty já conferido.
    let doTerminal = AbaDoTerminal.script(app: AbaDoTerminal.terminal, tty: "ttys003")
    conferir("Terminal procura a aba pelo dispositivo", doTerminal?.contains(#"if tty of t is "/dev/ttys003" then"#), true)
    conferir("Terminal não abre o app fechado", doTerminal?.hasPrefix(#"if application id "com.apple.Terminal" is not running"#), true)
    conferir("iTerm2 procura a sessão pelo dispositivo",
             AbaDoTerminal.script(app: AbaDoTerminal.iterm, tty: "ttys12")?.contains(#"if tty of s is "/dev/ttys12" then"#), true)
    conferir("outro app não tem script", AbaDoTerminal.script(app: "com.microsoft.VSCode", tty: "ttys003"), String?.none)
    conferir("tty inválido não entra no script", AbaDoTerminal.script(app: AbaDoTerminal.terminal, tty: #"ttys1" & beep & ""#), String?.none)
    lista = SessaoClaude.aplicar(m("a", .precisaDeVoce), a: lista, agora: t0 + 40)
    lista = SessaoClaude.aplicar(m("a", .subagente), a: lista, agora: t0 + 50)
    conferir("subagente usando ferramenta tira do precisa de você", lista.first?.estado, .trabalhando)
    lista = SessaoClaude.aplicar(m("a", .pronta), a: lista, agora: t0 + 60)
    lista = SessaoClaude.aplicar(m("a", .subagente), a: lista, agora: t0 + 70)
    conferir("subagente em segundo plano não liga o trabalhando", lista.first?.estado, .pronta)
    conferir("SessionEnd remove", SessaoClaude.aplicar(m("a", .fim), a: lista, agora: t0 + 80), [])
    conferir("SessionEnd de sessão desconhecida não cria", SessaoClaude.aplicar(m("z", .fim), a: lista, agora: t0 + 80).map(\.id), ["a"])

    var varias: [SessaoClaude] = []
    for (i, (id, evento)) in [("p1", MensagemClaude.Evento.pronta), ("t1", .trabalhando), ("p2", .pronta),
                              ("v1", .precisaDeVoce), ("t2", .trabalhando)].enumerated() {
        varias = SessaoClaude.aplicar(m(id, evento), a: varias, agora: t0 + Double(i))
    }
    conferir("ordem: precisa de você, trabalhando, pronta; recente primeiro", varias.map(\.id), ["v1", "t2", "t1", "p2", "p1"])
    var cheia: [SessaoClaude] = []
    for i in 0..<(SessaoClaude.maximo + 4) { cheia = SessaoClaude.aplicar(m("s\(i)", .pronta), a: cheia, agora: t0 + Double(i)) }
    conferir("lista não passa do máximo", cheia.count, SessaoClaude.maximo)
    conferir("sai a pronta mais antiga", cheia.contains { $0.id == "s0" }, false)

    let pronta = SessaoClaude(id: "p", pasta: "p", estado: .pronta, desde: t0, visto: t0, app: nil)
    let ocupada = SessaoClaude(id: "t", pasta: "t", estado: .trabalhando, desde: t0, visto: t0 + 3600, app: nil)
    conferir("pronta com 29 min fica", SessaoClaude.vivas([pronta], agora: t0 + 29 * 60).count, 1)
    conferir("pronta com 31 min some", SessaoClaude.vivas([pronta], agora: t0 + 31 * 60).count, 0)
    conferir("trabalhando há 2 h com sinal recente fica", SessaoClaude.vivas([ocupada], agora: t0 + 7200).count, 1)
    conferir("sem sinal por mais de 3 h some", SessaoClaude.vivas([ocupada], agora: t0 + 3600 + 3 * 3600 + 1).count, 0)

    // Avisos no mural, pelas mudanças de estado.
    let mural = Mural()
    let sessoes = SessoesClaude(mural: mural)
    sessoes.receber(m("a", .trabalhando), agora: t0)
    conferir("trabalhando não avisa", mural.atividades.map(\.id), [])
    sessoes.receber(m("a", .precisaDeVoce), agora: t0 + 1)
    conferir("precisa de você vai para o mural e fica", mural.atividades.map { "\($0.id) \($0.expira ?? -1)" }, ["claude-a 0.0"])
    conferir("o detalhe é a pasta", mural.atividades.first?.detalhe, "pasta-a")
    sessoes.receber(m("a", .precisaDeVoce), agora: t0 + 2)
    conferir("permission_prompt repetido não duplica", mural.atividades.count, 1)
    sessoes.receber(m("a", .trabalhando), agora: t0 + 3)
    conferir("saindo do precisa de você, o aviso sai", mural.atividades.map(\.id), [])
    sessoes.receber(m("a", .pronta), agora: t0 + 4)
    conferir("trabalhando → pronta avisa que terminou", mural.atividades.map(\.id), ["claude-fim-a"])
    mural.limpar()
    sessoes.receber(m("a", .pronta), agora: t0 + 5)
    conferir("idle_prompt depois do Stop não avisa de novo", mural.atividades.map(\.id), [])
    sessoes.receber(m("b", .precisaDeVoce), agora: t0 + 6)
    sessoes.receber(m("b", .fim), agora: t0 + 7)
    conferir("SessionEnd tira o aviso", mural.atividades.map(\.id), [])
    sessoes.receber(m("c", .precisaDeVoce), agora: t0)
    sessoes.varrer(agora: t0 + 4 * 3600)
    conferir("sessão expirada tira o aviso", mural.atividades.map(\.id), [])
    conferir("varredura limpa a lista", sessoes.sessoes.map(\.id), [])

    // Esc sem Stop, permissão recusada e eventos atrasados (revisão da v0.6).
    let esperando = SessaoClaude(id: "e", pasta: "e", estado: .precisaDeVoce, desde: t0, visto: t0, app: nil)
    conferir("precisa de você há 14 min continua", SessaoClaude.envelhecidas([esperando], agora: t0 + 14 * 60).map(\.estado), [.precisaDeVoce])
    conferir("precisa de você há 16 min vira pronta", SessaoClaude.envelhecidas([esperando], agora: t0 + 16 * 60).map(\.estado), [.pronta])
    let parada = SessaoClaude(id: "t", pasta: "t", estado: .trabalhando, desde: t0, visto: t0, app: nil)
    conferir("trabalhando sem sinal por 21 min vira pronta", SessaoClaude.envelhecidas([parada], agora: t0 + 21 * 60).map(\.estado), [.pronta])
    conferir("vira pronta a partir de agora (não some na hora)",
             SessaoClaude.vivas(SessaoClaude.envelhecidas([parada], agora: t0 + 21 * 60), agora: t0 + 21 * 60).count, 1)
    mural.limpar()
    sessoes.receber(m("d", .trabalhando), agora: t0)
    sessoes.receber(m("d", .precisaDeVoce), agora: t0 + 1)
    sessoes.varrer(agora: t0 + 16 * 60)
    conferir("esperando demais: o aviso preso sai", mural.atividades.map(\.id), [])
    conferir("e a varredura não diz que o Claude terminou", sessoes.sessoes.map(\.estado), [.pronta])
    let ultimo = t0 + 20 * 60
    sessoes.receber(m("f", .trabalhando), agora: ultimo)
    sessoes.receber(m("f", .fim), agora: ultimo + 1)
    sessoes.receber(m("f", .pronta), agora: ultimo + 2)
    conferir("Stop atrasado depois do SessionEnd não cria fantasma", sessoes.sessoes.contains { $0.id == "f" }, false)
    sessoes.receber(m("f", .inicio), agora: ultimo + 3)
    conferir("--resume com o mesmo id volta", sessoes.sessoes.contains { $0.id == "f" }, true)
}
