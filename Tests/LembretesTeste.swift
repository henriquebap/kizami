import Foundation

// Regras puras dos lembretes: quais vão para a ilha, em que ordem, e o texto do prazo. Sem EventKit nem permissão.
@MainActor func testarLembretes() {
    var calendario = Calendar(identifier: .gregorian)
    calendario.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    // 15/01/2027 10:00 em São Paulo.
    let agora = calendario.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 10))!
    let hoje = calendario.startOfDay(for: agora)
    func dia(_ d: Int) -> Date { calendario.date(byAdding: .day, value: d, to: hoje)! }
    func hora(_ h: Double) -> Date { hoje.addingTimeInterval(h * 3600) }
    func l(_ id: String, vence: Date? = nil, hora: Bool = false, prioridade: Int = 0, concluido: Bool = false) -> Lembrete {
        Lembrete(id: id, titulo: id, vence: vence, temHora: hora, prioridade: prioridade, concluido: concluido)
    }
    func ids(_ lista: [Lembrete]) -> [String] { Lembrete.proximos(lista, agora: agora, calendario: calendario).map(\.id) }

    conferir("atrasados e de hoje pelo prazo, antes dos sem data",
             ids([l("semData"), l("hoje15", vence: hora(15), hora: true), l("ontem", vence: dia(-1)), l("hoje9", vence: hora(9), hora: true)]),
             ["ontem", "hoje9", "hoje15"])
    conferir("no máximo 3", ids((1...5).map { l("x\($0)") }).count, 3)
    conferir("concluído não entra", ids([l("feito", vence: dia(-1), concluido: true), l("a")]), ["a"])
    conferir("amanhã em diante fica de fora", ids([l("amanha", vence: dia(1)), l("hora", vence: dia(1).addingTimeInterval(60), hora: true)]), [])
    conferir("hoje sem hora entra", ids([l("hoje", vence: hoje)]), ["hoje"])
    conferir("sem data: alta antes de baixa, nenhuma por último",
             ids([l("nenhuma"), l("baixa", prioridade: 9), l("alta", prioridade: 1)]), ["alta", "baixa", "nenhuma"])
    conferir("mesmo prazo: a prioridade desempata", ids([l("b", vence: hoje), l("a", vence: hoje, prioridade: 5)]), ["a", "b"])
    conferir("mesmo prazo e prioridade: o título desempata", ids([l("b"), l("a")]), ["a", "b"])
    conferir("sem data só sobra o que cabe", ids([l("s"), l("1", vence: dia(-3)), l("2", vence: dia(-2)), l("3", vence: dia(-1))]),
             ["1", "2", "3"])

    // Atrasado e o texto do prazo
    conferir("hora que passou: atrasado", l("a", vence: hora(9), hora: true).atrasado(agora: agora, calendario: calendario), true)
    conferir("hora que vem: no prazo", l("a", vence: hora(11), hora: true).atrasado(agora: agora, calendario: calendario), false)
    conferir("hoje sem hora: no prazo o dia todo", l("a", vence: hoje).atrasado(agora: agora, calendario: calendario), false)
    conferir("ontem sem hora: atrasado", l("a", vence: dia(-1)).atrasado(agora: agora, calendario: calendario), true)
    conferir("sem data nunca atrasa", l("a").atrasado(agora: agora, calendario: calendario), false)
    conferir("texto: atrasado", l("a", vence: dia(-1)).quando(agora: agora, calendario: calendario), "atrasado")
    conferir("texto: hoje", l("a", vence: hoje).quando(agora: agora, calendario: calendario), "hoje")
    conferir("texto: sem data, nada", l("a").quando(agora: agora, calendario: calendario), nil)
    conferir("texto: com hora, a hora", l("a", vence: hora(15), hora: true).quando(agora: agora, calendario: calendario) != nil, true)
}
