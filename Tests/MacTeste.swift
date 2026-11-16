import Foundation

// Regras puras do Mac: avisos de bateria, emblemas que subiram e a lista do microfone. Sem IOKit, Dock nem Core Audio.
@MainActor func testarMac() {
    // Bateria: aplica as leituras em sequência e junta os avisos.
    func avisos(_ leituras: [Bateria?], memoria inicial: Bateria.Memoria = Bateria.Memoria()) -> [Bateria.Aviso] {
        var memoria = inicial
        var saida: [Bateria.Aviso] = []
        for leitura in leituras {
            let (aviso, nova) = Bateria.decidir(leitura, memoria)
            memoria = nova
            if let aviso { saida.append(aviso) }
        }
        return saida
    }
    func fora(_ p: Int) -> Bateria { Bateria(porcento: p, carregando: false, ligadaNaTomada: false) }
    func tomada(_ p: Int) -> Bateria { Bateria(porcento: p, carregando: p < 100, ligadaNaTomada: true) }

    conferir("sem bateria: nada", avisos([nil, nil]), [])
    conferir("descarregando acima de 20: nada", avisos([fora(50), fora(30), fora(21)]), [])
    conferir("cruza 20: um aviso", avisos([fora(22), fora(20), fora(19), fora(18)]), [.fraca(20)])
    conferir("cruza 20 e 10", avisos([fora(21), fora(20), fora(15), fora(10), fora(9)]), [.fraca(20), .fraca(10)])
    conferir("pula de 21 para 9: um aviso só", avisos([fora(21), fora(9), fora(8)]), [.fraca(9)])
    conferir("abrir já em 15%: avisa", avisos([fora(15)]), [.fraca(15)])
    conferir("oscila em volta de 20 sem passar de 25: não repete",
             avisos([fora(20), tomada(22), fora(22), fora(20)]), [.fraca(20), .carregando])
    conferir("carregou acima de 25: rearma",
             avisos([fora(20), tomada(26), fora(26), fora(20)]), [.fraca(20), .carregando, .fraca(20)])
    conferir("na tomada não avisa fraca", avisos([tomada(15), tomada(9)]), [])
    conferir("plugou: carregando", avisos([fora(50), tomada(50)]), [.carregando])
    conferir("abrir já na tomada: nada", avisos([tomada(50), tomada(51)]), [])
    conferir("chegou a 100 na tomada: completa, uma vez", avisos([tomada(99), tomada(100), tomada(100)]), [.completa])
    conferir("abrir já cheio na tomada: nada", avisos([tomada(100), tomada(100)]), [])
    conferir("tirou e pôs de novo cheio: completa de novo",
             avisos([tomada(99), tomada(100), fora(100), tomada(100)]), [.completa, .completa])
    conferir("100 e caiu para 99 na tomada: não repete", avisos([tomada(99), tomada(100), tomada(99), tomada(100)]), [.completa])
    conferir("leitura sumiu (nil) não mexe na memória",
             Bateria.decidir(nil, Bateria.Memoria(tomada: false, avisou20: true)).memoria, Bateria.Memoria(tomada: false, avisou20: true))

    // Atividade do aviso: id fixo, para um aviso substituir o outro na ilha.
    conferir("aviso de bateria usa mac-bateria", Bateria.Aviso.fraca(9).atividade(porcento: 9).id, "mac-bateria")
    conferir("carregando expira em 4 s", Bateria.Aviso.carregando.atividade(porcento: 50).expira, 4)
    conferir("a 10% é vermelho", Bateria.Aviso.fraca(10).atividade(porcento: 10).cor, "vermelho")

    // Emblemas do Dock
    func e(_ bundle: String, _ rotulo: String) -> Emblema { Emblema(bundle: bundle, nome: bundle, rotulo: rotulo) }
    func novidades(_ antes: [Emblema], _ depois: [Emblema]) -> [String] {
        Emblema.novidades(antes: antes, depois: depois).map(\.bundle)
    }
    conferir("subiu: avisa", novidades([e("zap", "3")], [e("zap", "4")]), ["zap"])
    conferir("igual: nada", novidades([e("zap", "3")], [e("zap", "3")]), [])
    conferir("desceu: nada", novidades([e("mail", "12")], [e("mail", "10")]), [])
    conferir("• não é número: nada", novidades([], [e("zap", "•")]), [])
    conferir("app novo com número: avisa", novidades([e("mail", "12")], [e("mail", "12"), e("zap", "1")]), ["zap"])
    conferir("de • para 2: avisa", novidades([e("zap", "•")], [e("zap", "2")]), ["zap"])
    conferir("99+ subindo de 98: avisa", novidades([e("zap", "98")], [e("zap", "99+")]), ["zap"])
    conferir("99+ igual: nada", novidades([e("zap", "99+")], [e("zap", "99+")]), [])
    conferir("emblema sumiu: nada", novidades([e("zap", "3")], []), [])
    conferir("número do rótulo", e("x", "12").numero, 12)
    conferir("rótulo vazio não é número", e("x", "").numero, nil)

    // Microfone
    let kizami = "io.github.henriquebap.kizami"
    conferir("o próprio Kizami fica de fora", Mac.microfone(["us.zoom.xos", kizami], antes: [], proprio: kizami), ["us.zoom.xos"])
    conferir("ordem estável: quem já estava fica na frente",
             Mac.microfone(["com.apple.Safari", "us.zoom.xos"], antes: ["us.zoom.xos"], proprio: kizami),
             ["us.zoom.xos", "com.apple.Safari"])
    conferir("dois processos do mesmo app: um só",
             Mac.microfone(["com.google.Chrome", "com.google.Chrome"], antes: [], proprio: kizami), ["com.google.Chrome"])
    conferir("quem fechou sai", Mac.microfone([], antes: ["us.zoom.xos"], proprio: kizami), [])
}
