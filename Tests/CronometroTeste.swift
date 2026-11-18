import Foundation

// Timer e pomodoro: o texto da contagem, o passo seguinte e o ciclo iniciar → pausar → continuar → parar, com datas explícitas.
@MainActor func testarCronometro() {
    conferir("zero", Cronometro.texto(0), "0:00")
    conferir("0,4 s faltando não mostra 0:00", Cronometro.texto(0.4), "0:01")
    conferir("59,9 s arredonda para 1:00", Cronometro.texto(59.9), "1:00")
    conferir("um minuto", Cronometro.texto(60), "1:00")
    conferir("um segundo a menos que 5 min", Cronometro.texto(299), "4:59")
    conferir("foco inteiro", Cronometro.texto(25 * 60), "25:00")
    conferir("uma hora", Cronometro.texto(3600), "1:00:00")
    conferir("hora, minutos e segundos", Cronometro.texto(3723), "1:02:03")
    conferir("negativo vira zero", Cronometro.texto(-5), "0:00")
    conferir("NaN vira zero", Cronometro.texto(.nan), "0:00")

    // Ajustes e estado numa suíte só do teste: o domínio do app (e o do executável de teste) fica intocado.
    let suite = "io.github.henriquebap.kizami.teste-cronometro"
    let padroes = UserDefaults(suiteName: suite)!
    padroes.removePersistentDomain(forName: suite)
    defer { padroes.removePersistentDomain(forName: suite) }

    // Pausar depois da hora (o Mac acordou antes da tarefa): termina em vez de ficar "Pausado 0:00".
    let atrasado = Cronometro(mural: Mural(), padroes: padroes)
    let inicio = Date(timeIntervalSince1970: 1_800_000_000)
    atrasado.iniciar(minutos: 1, modo: .foco, agora: inicio)
    atrasado.pausar(agora: inicio.addingTimeInterval(61))
    conferir("pausar depois do fim termina", atrasado.ativo, false)
    atrasado.parar()

    typealias Preset = Cronometro.Preset
    conferir("depois do foco, a pausa configurada", Cronometro.proximo(depois: .foco, foco: 30, pausa: 7), Preset(minutos: 7, modo: .pausa))
    conferir("depois da pausa, o foco configurado", Cronometro.proximo(depois: .pausa, foco: 30, pausa: 7), Preset(minutos: 30, modo: .foco))
    conferir("timer livre não encadeia", Cronometro.proximo(depois: .livre, foco: 30, pausa: 7), nil)

    conferir("livres: vírgulas e espaços", Cronometro.livres(de: "10, 15 50"), [10, 15, 50])
    conferir("livres: lixo sai", Cronometro.livres(de: "abc, 10min, 20,, ; 5.5"), [20])
    conferir("livres: fora da faixa sai", Cronometro.livres(de: "0 -5 241 240 1"), [240, 1])
    conferir("livres: repetidos saem, ordem fica", Cronometro.livres(de: "15 10 15 10 5"), [15, 10, 5])
    conferir("livres: corta em 3", Cronometro.livres(de: "1 2 3 4 5"), [1, 2, 3])
    conferir("livres: vazio", Cronometro.livres(de: "  "), [])
    conferir("presets: foco, pausa e livres", Cronometro.presets(foco: 25, pausa: 5, livres: [10, 15]),
             [Preset(minutos: 25, modo: .foco), Preset(minutos: 5, modo: .pausa), Preset(minutos: 10, modo: .livre), Preset(minutos: 15, modo: .livre)])
    conferir("presets: no máximo 5 botões", Cronometro.presets(foco: 25, pausa: 5, livres: [1, 2, 3, 4]).count, 5)
    conferir("presets: foco e pausa na faixa", Cronometro.presets(foco: 999, pausa: 0, livres: []),
             [Preset(minutos: 180, modo: .foco), Preset(minutos: 1, modo: .pausa)])

    let padrao = Cronometro(mural: Mural(), padroes: padroes)
    conferir("padrões: 25, 5 e [10, 15]", [padrao.minutosFoco, padrao.minutosPausa] + padrao.livres, [25, 5, 10, 15])
    conferir("padrões: texto do campo", padrao.textoLivres, "10, 15")
    padrao.minutosFoco = 40
    padrao.textoLivres = "3, x, 3 90"
    padrao.aplicarTextoLivres()
    conferir("campo confirmado mostra o que ficou", padrao.textoLivres, "3, 90")
    conferir("guardado: relido por outro", Cronometro(mural: Mural(), padroes: padroes).presets.map(\.minutos), [40, 5, 3, 90])
    padroes.set(999, forKey: Cronometro.chaveFoco)
    padroes.set("lixo", forKey: Cronometro.chavePausa)
    padroes.set([0, 10, 10, 300, 20, 30, 40], forKey: Cronometro.chaveLivres)
    let sujo = Cronometro(mural: Mural(), padroes: padroes)
    conferir("disco sujo passa pelas regras", [sujo.minutosFoco, sujo.minutosPausa] + sujo.livres, [180, 5, 10, 20, 30])

    let mural = Mural()
    padroes.removePersistentDomain(forName: suite)
    let cronometro = Cronometro(mural: mural, padroes: padroes)
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    conferir("parado: inativo", cronometro.ativo, false)
    conferir("parado: nada falta", cronometro.restante(agora: t0), 0)
    cronometro.iniciar(minutos: 0, modo: .livre, agora: t0)
    conferir("zero minutos não inicia", cronometro.ativo, false)

    cronometro.iniciar(minutos: 25, modo: .foco, agora: t0)
    conferir("iniciou: ativo e no modo foco", [cronometro.ativo, cronometro.modo == .foco, cronometro.pausado], [true, true, false])
    conferir("10 s depois", cronometro.restante(agora: t0 + 10), 1490)
    cronometro.pausar(agora: t0 + 100)
    conferir("pausou: ainda ativo", [cronometro.ativo, cronometro.pausado], [true, true])
    conferir("pausado não anda", cronometro.restante(agora: t0 + 1000), 1400)
    cronometro.pausar(agora: t0 + 2000)
    conferir("pausar de novo não muda nada", cronometro.restante(agora: t0 + 3000), 1400)
    cronometro.continuar(agora: t0 + 1000)
    conferir("continuou de onde parou", cronometro.restante(agora: t0 + 1000), 1400)
    conferir("e volta a andar", cronometro.restante(agora: t0 + 1060), 1340)
    conferir("passou do fim: zero", cronometro.restante(agora: t0 + 9000), 0)
    cronometro.parar()
    conferir("parou: inativo", [cronometro.ativo, cronometro.pausado], [false, false])
    conferir("parado: nada falta de novo", cronometro.restante(agora: t0 + 1060), 0)

    // Fim do foco: o aviso entra na ilha, e o clique nele começa a pausa de 5.
    cronometro.iniciar(minutos: 25, modo: .foco, agora: t0)
    cronometro.terminar()
    conferir("terminou: inativo", cronometro.ativo, false)
    conferir("aviso de fim na ilha", mural.atividades.map(\.id), [Cronometro.idAviso])
    conferir("aviso alto, com prazo", mural.atividades.first.map { "\($0.prioridade ?? "") \($0.expira ?? 0)" }, "alta 120.0")
    conferir("pomodoro: o aviso abre", mural.podeAbrir(Cronometro.idAviso), true)
    mural.abrir(Cronometro.idAviso)
    conferir("clique começa a pausa", [cronometro.ativo, cronometro.modo == .pausa], [true, true])
    conferir("pausa de 5 min", Cronometro.texto(cronometro.restante(agora: .now)), "5:00")
    conferir("clique tira o aviso", mural.atividades.isEmpty, true)
    cronometro.terminar()
    conferir("fim da pausa também abre", mural.podeAbrir(Cronometro.idAviso), true)

    // Com foco e pausa dos Ajustes, o clique no aviso usa os minutos configurados.
    cronometro.minutosFoco = 30
    cronometro.minutosPausa = 7
    mural.abrir(Cronometro.idAviso)
    conferir("fim da pausa: foco configurado", [cronometro.modo == .foco, Cronometro.texto(cronometro.restante(agora: .now)) == "30:00"], [true, true])
    cronometro.terminar()
    mural.abrir(Cronometro.idAviso)
    conferir("fim do foco: pausa configurada", [cronometro.modo == .pausa, Cronometro.texto(cronometro.restante(agora: .now)) == "7:00"], [true, true])
    cronometro.terminar()
    cronometro.iniciar(minutos: 10, modo: .livre, agora: t0)
    conferir("novo timer tira o aviso velho", mural.atividades.isEmpty, true)
    cronometro.terminar()
    conferir("timer livre: aviso sem clique", [mural.atividades.count == 1, mural.podeAbrir(Cronometro.idAviso)], [true, false])
    cronometro.parar()

    cronometro.iniciar(minutos: 25, modo: .foco, agora: t0)
    conferir("Não Perturbe desligado nos Ajustes: nada ligado", cronometro.naoPerturbeLigado, false)
    cronometro.parar()
    mural.remover(id: Cronometro.idAviso)
    testarNaoPerturbe(padroes)

    testarEstadoSalvo(padroes)
}

/// Não Perturbe: só a troca de foco para fora (ou de volta) roda um atalho, e o "ligado" sobrevive a reiniciar.
/// O atalho é falso: nada roda no app Atalhos; aqui conta o estado que o Kizami acha que deixou.
@MainActor private func testarNaoPerturbe(_ padroes: UserDefaults) {
    padroes.removeObject(forKey: Cronometro.chaveEstado)
    let falso: @Sendable (String) async -> Int32 = { _ in 0 }
    let t0 = Date.now
    let c = Cronometro(mural: Mural(), padroes: padroes, executarAtalho: falso)
    c.naoPerturbe = true
    c.iniciar(minutos: 25, modo: .foco, agora: t0)
    conferir("foco liga", c.naoPerturbeLigado, true)
    c.pausar(agora: t0 + 10)
    conferir("foco pausado continua ligado", c.naoPerturbeLigado, true)
    c.iniciar(minutos: 5, modo: .pausa, agora: t0)
    conferir("pausa do pomodoro desliga", c.naoPerturbeLigado, false)
    c.iniciar(minutos: 25, modo: .foco, agora: t0)
    c.iniciar(minutos: 10, modo: .livre, agora: t0)
    conferir("timer livre desliga", c.naoPerturbeLigado, false)
    c.iniciar(minutos: 25, modo: .foco, agora: t0)
    c.terminar()
    conferir("fim do foco desliga", c.naoPerturbeLigado, false)
    c.iniciar(minutos: 25, modo: .foco, agora: t0)
    c.parar()
    conferir("parar desliga", c.naoPerturbeLigado, false)
    c.iniciar(minutos: 25, modo: .foco, agora: t0)
    c.naoPerturbe = false
    conferir("desligar a opção no meio do foco desliga", c.naoPerturbeLigado, false)
    c.naoPerturbe = true
    conferir("ligar a opção no meio do foco liga", c.naoPerturbeLigado, true)

    // O app fecha no meio do foco e reabre: foco ainda correndo continua ligado, sem rodar de novo.
    conferir("reabriu no foco: ligado", Cronometro(mural: Mural(), padroes: padroes, executarAtalho: falso).naoPerturbeLigado, true)
    // Reabre muito depois do fim: o estado é velho demais para avisar, mas o Não Perturbe desliga.
    padroes.set(Cronometro.codificar(.init(modo: .foco, fim: t0 - 5 * 3600)), forKey: Cronometro.chaveEstado)
    let tarde = Cronometro(mural: Mural(), padroes: padroes, executarAtalho: falso)
    conferir("reabriu horas depois: desligado", [tarde.ativo, tarde.naoPerturbeLigado], [false, false])
    // Fecha com o foco pausado e reabre: parar ainda desliga.
    tarde.iniciar(minutos: 25, modo: .foco, agora: t0)
    tarde.pausar(agora: t0 + 10)
    let pausado = Cronometro(mural: Mural(), padroes: padroes, executarAtalho: falso)
    conferir("reabriu pausado: ligado", [pausado.pausado, pausado.naoPerturbeLigado], [true, true])
    pausado.parar()
    conferir("parar depois de reabrir desliga", pausado.naoPerturbeLigado, false)
    padroes.removeObject(forKey: Cronometro.chaveNaoPerturbe)
}

/// O timer sobrevive a reiniciar o app: a regra pura sobre o que veio do disco e o ciclo guardar → reabrir.
@MainActor private func testarEstadoSalvo(_ padroes: UserDefaults) {
    typealias Salvo = Cronometro.Salvo
    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    conferir("estado: ida e volta", Cronometro.decodificar(Cronometro.codificar(Salvo(modo: .pausa, restante: 90))), Salvo(modo: .pausa, restante: 90))
    conferir("estado: lixo vira nil", Cronometro.decodificar(Data("lixo".utf8)), nil)
    conferir("estado: modo desconhecido vira nil", Cronometro.decodificar(Data(#"{"modo":"sono","restante":60}"#.utf8)), nil)
    conferir("restaurar: nada salvo", Cronometro.restaurar(nil, agora: t0), .nada)
    conferir("restaurar: fim no futuro volta a correr", Cronometro.restaurar(Salvo(modo: .foco, fim: t0 + 600), agora: t0), .rodar(.foco, fim: t0 + 600))
    conferir("restaurar: pausado volta pausado", Cronometro.restaurar(Salvo(modo: .livre, restante: 300), agora: t0), .pausado(.livre, restante: 300))
    conferir("restaurar: fim há 10 min avisa", Cronometro.restaurar(Salvo(modo: .foco, fim: t0 - 600), agora: t0), .terminou(.foco))
    conferir("restaurar: fim há 2 h só limpa", Cronometro.restaurar(Salvo(modo: .foco, fim: t0 - 7200), agora: t0), .nada)
    conferir("restaurar: fim e restante juntos é lixo", Cronometro.restaurar(Salvo(modo: .foco, fim: t0 + 60, restante: 60), agora: t0), .nada)
    conferir("restaurar: restante zero é lixo", Cronometro.restaurar(Salvo(modo: .foco, restante: 0), agora: t0), .nada)
    conferir("restaurar: fim a um dia é lixo", Cronometro.restaurar(Salvo(modo: .livre, fim: t0 + 86_400), agora: t0), .nada)

    padroes.removePersistentDomain(forName: "io.github.henriquebap.kizami.teste-cronometro")
    let antes = Cronometro(mural: Mural(), padroes: padroes)
    antes.iniciar(minutos: 25, modo: .foco)
    let depois = Cronometro(mural: Mural(), padroes: padroes)
    conferir("reabriu rodando: mesmo fim e modo", [depois.fim == antes.fim, depois.modo == .foco, depois.pausado], [true, true, false])
    depois.pausar()
    let pausado = Cronometro(mural: Mural(), padroes: padroes)
    conferir("reabriu pausado", [pausado.pausado, pausado.restante(agora: .now) == depois.restante(agora: .now)], [true, true])
    antes.parar()
    pausado.parar()
    conferir("parar limpa o disco", padroes.data(forKey: Cronometro.chaveEstado), nil)
    conferir("reabriu parado", Cronometro(mural: Mural(), padroes: padroes).ativo, false)

    let mural = Mural()
    padroes.set(Cronometro.codificar(Salvo(modo: .foco, fim: .now - 600)), forKey: Cronometro.chaveEstado)
    let recente = Cronometro(mural: mural, padroes: padroes)
    conferir("fim recente com o app fechado: parado, com aviso", [recente.ativo, mural.podeAbrir(Cronometro.idAviso)], [false, true])
    conferir("fim recente: disco limpo", padroes.data(forKey: Cronometro.chaveEstado), nil)

    let muralVelho = Mural()
    padroes.set(Cronometro.codificar(Salvo(modo: .foco, fim: .now - 7200)), forKey: Cronometro.chaveEstado)
    conferir("fim antigo: parado", Cronometro(mural: muralVelho, padroes: padroes).ativo, false)
    conferir("fim antigo: sem aviso, disco limpo", [muralVelho.atividades.isEmpty, padroes.data(forKey: Cronometro.chaveEstado) == nil], [true, true])

    padroes.set(Data("lixo".utf8), forKey: Cronometro.chaveEstado)
    conferir("lixo no disco: parado", Cronometro(mural: Mural(), padroes: padroes).ativo, false)
    conferir("lixo no disco: limpo", padroes.data(forKey: Cronometro.chaveEstado), nil)
}
