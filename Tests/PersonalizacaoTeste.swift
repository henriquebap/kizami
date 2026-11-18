import Foundation

/// As escolhas da ilha: abas salvas, a ordem das asas e a asa da vez.
@MainActor func testarPersonalizacao() {
    conferir("abas: nada salvo, a ordem padrão", Personalizacao.abas(de: nil), Aba.doCabecalho)
    conferir("abas: Início volta se sumiu", Personalizacao.abas(de: ["kanji", "hoje"]), [.inicio, .kanji, .hoje])
    conferir("abas: lixo, repetido e espelho saem",
             Personalizacao.abas(de: ["hoje", "xyz", "hoje", "espelho", "inicio"]), [.hoje, .inicio])
    conferir("abas: lista vazia salva fica só com o Início", Personalizacao.abas(de: []), [.inicio])

    conferir("asas: nada salvo, a ordem padrão", Personalizacao.asas(de: nil), Asa.ordenaveis)
    conferir("asas: as que faltam entram no lugar da ordem padrão", Personalizacao.asas(de: ["tocando", "placar"]),
             [.reuniao, .timer, .atividades, .tocando, .placar])
    conferir("asas: ordem antiga sem a reunião ganha a reunião na frente",
             Personalizacao.asas(de: ["tocando", "timer", "atividades", "placar"]), [.reuniao, .tocando, .timer, .atividades, .placar])
    conferir("asas: só as ordenáveis", Personalizacao.asas(de: ["nada", "bandeja", "timer"]),
             [.reuniao, .timer, .atividades, .placar, .tocando])

    func asa(_ ordem: [Asa], importante: Bool = false, _ tem: Set<Asa>) -> Asa {
        Personalizacao.asa(ordem: ordem, importante: importante) { tem.contains($0) }
    }
    conferir("asa: o primeiro da ordem que tem algo", asa(Asa.ordenaveis, [.atividades, .tocando]), .atividades)
    conferir("asa: reunião chegando antes do timer, por padrão", asa(Asa.ordenaveis, [.timer, .reuniao]), .reuniao)
    conferir("asa: timer antes dos avisos, por padrão", asa(Asa.ordenaveis, [.atividades, .timer]), .timer)
    conferir("asa: aviso importante passa na frente do timer", asa(Asa.ordenaveis, importante: true, [.atividades, .timer]),
             .atividades)
    conferir("asa: música primeiro, se a pessoa quis", asa([.tocando, .timer, .atividades, .placar], [.timer, .tocando]), .tocando)
    conferir("asa: microfone depois das ordenáveis", asa(Asa.ordenaveis, [.privacidade, .bandeja]), .privacidade)
    conferir("asa: nada", asa(Asa.ordenaveis, []), .nada)

    conferir("mover: sobe", Personalizacao.mover(2, -1, em: [1, 2, 3]), [2, 1, 3])
    conferir("mover: na ponta não muda", Personalizacao.mover(1, -1, em: [1, 2, 3]), [1, 2, 3])
    conferir("mover: fora da lista não muda", Personalizacao.mover(9, 1, em: [1, 2, 3]), [1, 2, 3])

    // Persistência num domínio de teste, para não sujar o do app.
    let suite = "kizami.teste.personalizacao"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let p = Personalizacao(defaults: defaults)
    p.alternar(.kanji)
    p.alternar(.bandeja)
    p.asas = Personalizacao.mover(.tocando, -1, em: p.asas)
    let relida = Personalizacao(defaults: defaults)
    conferir("salva: a aba desligada", relida.abas.contains(.kanji), false)
    conferir("salva: a seção escondida", relida.mostra(.bandeja), false)
    conferir("salva: a ordem das asas", relida.asas, [.reuniao, .timer, .atividades, .tocando, .placar])
    conferir("abre na primeira aba", relida.abaInicial, .inicio)
    conferir("opacidade: sem nada salvo, o vidro escurecido", Personalizacao.opacidade(nil), Personalizacao.opacidadePadrao)
    conferir("opacidade: abaixo do mínimo sobe para o mínimo", Personalizacao.opacidade(0.1), Personalizacao.opacidadeMinima)
    conferir("opacidade: acima de 1 fica em 1", Personalizacao.opacidade(3.0), 1)
    conferir("opacidade: valor do meio fica", Personalizacao.opacidade(0.7), 0.7)
    conferir("opacidade: outro tipo salvo vira o padrão", Personalizacao.opacidade("0.5"), Personalizacao.opacidadePadrao)
    conferir("opacidade: NaN vira o padrão", Personalizacao.opacidade(Double.nan), Personalizacao.opacidadePadrao)
    defaults.removePersistentDomain(forName: suite)

}
