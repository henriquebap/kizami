import Foundation

// Regras puras da agenda: qual evento mostrar, que link abrir e quando lembrar. Sem EventKit nem permissão.
@MainActor func testarAgenda() {
    let agora = Date(timeIntervalSince1970: 1_800_000_000)
    func evento(_ id: String, em minutos: Double, dura: Double = 30, diaInteiro: Bool = false, recusado: Bool = false) -> EventoAgenda {
        let inicio = agora.addingTimeInterval(minutos * 60)
        return EventoAgenda(id: id, titulo: id, inicio: inicio, fim: inicio.addingTimeInterval(dura * 60),
                            diaInteiro: diaInteiro, recusado: recusado)
    }

    // Próximo evento
    conferir("o mais cedo dos que vêm", EventoAgenda.proximo([evento("b", em: 90), evento("a", em: 30)], agora: agora)?.id, "a")
    conferir("dia inteiro não conta", EventoAgenda.proximo([evento("feriado", em: -60, dura: 1440, diaInteiro: true),
                                                            evento("a", em: 30)], agora: agora)?.id, "a")
    conferir("recusado não conta", EventoAgenda.proximo([evento("nao", em: 5, recusado: true)], agora: agora), nil)
    conferir("começou há 5 min: ainda é ele", EventoAgenda.proximo([evento("atual", em: -5), evento("a", em: 30)], agora: agora)?.id, "atual")
    conferir("começou há 15 min: passa para o próximo",
             EventoAgenda.proximo([evento("atual", em: -15, dura: 60), evento("a", em: 30)], agora: agora)?.id, "a")
    conferir("já acabou", EventoAgenda.proximo([evento("velho", em: -8, dura: 5)], agora: agora), nil)
    conferir("daqui a 13 h fica fora", EventoAgenda.proximo([evento("longe", em: 13 * 60)], agora: agora), nil)
    conferir("daqui a 11 h entra", EventoAgenda.proximo([evento("perto", em: 11 * 60)], agora: agora)?.id, "perto")
    conferir("nenhum", EventoAgenda.proximo([], agora: agora), nil)

    // Link da reunião
    func link(_ url: String? = nil, local: String? = nil, notas: String? = nil) -> String? {
        EventoAgenda.link(url: url.flatMap { URL(string: $0) }, local: local, notas: notas)?.absoluteString
    }
    conferir("Meet no campo URL", link("https://meet.google.com/abc-defg-hij"), "https://meet.google.com/abc-defg-hij")
    conferir("Zoom com subdomínio", link("https://us02web.zoom.us/j/123?pwd=x"), "https://us02web.zoom.us/j/123?pwd=x")
    conferir("Teams nas notas, entre <>",
             link(notas: "Participe:\n<https://teams.microsoft.com/l/meetup-join/19%3a1> ou ligue"),
             "https://teams.microsoft.com/l/meetup-join/19%3a1")
    conferir("FaceTime no local", link(local: "https://facetime.apple.com/join#v=1&p=x"), "https://facetime.apple.com/join#v=1&p=x")
    conferir("http não passa", link("http://meet.google.com/abc"), nil)
    conferir("sem esquema não passa", link(local: "meet.google.com/abc"), nil)
    conferir("domínio parecido não passa", link("https://meet.google.com.evil.com/abc"), nil)
    conferir("sufixo sem ponto não passa", link("https://evilzoom.us/j/1"), nil)
    conferir("usuário no endereço não engana o host", link("https://meet.google.com@evil.com/abc"), nil)
    conferir("zoommtg não passa", link("zoommtg://zoom.us/join?confno=1"), nil)
    conferir("o primeiro aceito vence: URL ruim, local bom",
             link("https://exemplo.com/x", local: "https://whereby.com/sala", notas: "https://meet.google.com/zzz"),
             "https://whereby.com/sala")
    conferir("nas notas, pula o link de fora da lista",
             link(notas: "Pauta: https://docs.exemplo.com/p — sala: https://meet.google.com/abc"), "https://meet.google.com/abc")
    conferir("host em maiúsculas", link("https://MEET.Google.com/abc") != nil, true)

    // Lembretes
    func avisos(_ eventos: [EventoAgenda], _ avisados: Set<String> = []) -> [EventoAgenda.Aviso] {
        EventoAgenda.lembretes(eventos, agora: agora, avisados: avisados).map(\.aviso)
    }
    conferir("a 15 min avisa", avisos([evento("a", em: 15)]), [.faltam(minutos: 15)])
    conferir("a 14,5 min arredonda para cima", avisos([evento("a", em: 14.5)]), [.faltam(minutos: 15)])
    conferir("a 16 min ainda não", avisos([evento("a", em: 16)]), [])
    let a = evento("a", em: 10)
    let primeiro = EventoAgenda.lembretes([a], agora: agora, avisados: [])
    conferir("não avisa duas vezes", avisos([a], Set(primeiro.map(\.chave))), [])
    conferir("acordou 3 min antes: em 3 min", avisos([evento("a", em: 3)]), [.faltam(minutos: 3)])
    conferir("acordou 20 min depois do início: nada", avisos([evento("a", em: -20, dura: 60)]), [])
    conferir("acordou 2 min depois do início: nada", avisos([evento("a", em: -2)]), [])
    conferir("no início: começando agora", avisos([evento("a", em: -0.5)]), [.comecando])
    conferir("começando agora não repete", avisos([evento("a", em: -0.5)], ["a#0"]), [])
    conferir("o de 15 min avisado não impede o do início", avisos([evento("a", em: 0)], ["a#15"]), [.comecando])
    conferir("dia inteiro e recusado não avisam",
             avisos([evento("d", em: 0, diaInteiro: true), evento("r", em: 10, recusado: true)]), [])
}
