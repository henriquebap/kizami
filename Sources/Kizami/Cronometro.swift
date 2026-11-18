import Foundation
import Observation

/// O timer da ilha, com o pomodoro: foco e pausa com os minutos dos Ajustes, e o clique no aviso de fim começa o passo seguinte.
/// Guarda a hora do fim, não um contador: a contagem na tela sai de `restante(agora:)`, e dormir o Mac não a atrasa.
/// O estado vai para o disco (`chaveEstado`) a cada mudança: reiniciar o app, ou ele cair, não perde o timer.
@MainActor @Observable
final class Cronometro {
    /// O valor cru é o que vai para o disco: renomear um caso faz o estado salvo antes ser descartado como lixo.
    enum Modo: String, Codable, Hashable, Sendable {
        case foco, pausa, livre

        var nome: String {
            switch self {
            case .foco: String(localized: "Foco")
            case .pausa: String(localized: "Pausa")
            case .livre: String(localized: "Timer")
            }
        }

        var simbolo: String {
            switch self {
            case .foco: "brain.head.profile"
            case .pausa: "cup.and.saucer.fill"
            case .livre: "timer"
            }
        }

        /// Uma das `Atividade.cores`: a do aviso de fim.
        var cor: String {
            switch self {
            case .foco: "vermelho"
            case .pausa: "verde"
            case .livre: "azul"
            }
        }
    }

    /// Um botão da aba Timer. Minutos e modo juntos servem de id: um livre de 25 não colide com o foco de 25.
    struct Preset: Hashable, Sendable {
        let minutos: Int
        let modo: Modo
    }

    static let chaveFoco = "timer.foco"
    static let chavePausa = "timer.pausa"
    static let chaveLivres = "timer.livres"
    static let chaveEstado = "timer.estado"
    static let chaveNaoPerturbe = "timer.naoPerturbe"
    /// O macOS não deixa um app ligar o Foco por API pública; o app Atalhos deixa (ação "Definir Foco").
    /// A pessoa cria estes dois atalhos, e o que eles ligam (Não Perturbe ou outro Foco) é escolha dela.
    static let atalhoLigar = "Kizami Foco"
    static let atalhoDesligar = "Kizami Fim do Foco"
    static let focoPadrao = 25
    static let pausaPadrao = 5
    static let livresPadrao = [10, 15]
    static let faixaFoco = 1...180
    static let faixaPausa = 1...60
    static let faixaLivre = 1...240
    /// Foco, pausa e três livres: cinco botões é o que cabe na largura da ilha, como os seis atalhos.
    static let maxLivres = 3
    static let idAviso = "kizami-timer"
    /// O aviso de fim fica um pouco na ilha: dá tempo de voltar ao Mac e clicar para o próximo passo.
    static let expiraAviso: Double = 120
    /// Fim que passou com o app fechado: até 1 h depois ainda avisa (o app caiu ou reiniciou no meio do foco e a pessoa
    /// quer saber que acabou); depois disso o aviso, e o convite para a pausa de um ciclo de horas atrás, só atrapalham.
    static let janelaAvisoAtrasado: TimeInterval = 3600
    /// Nenhum preset passa do maior timer livre: mais que isso no disco é lixo (ou o relógio do Mac voltou muito).
    static let maximoSalvo = TimeInterval(faixaLivre.upperBound * 60)

    /// O que fica no disco: o modo e o fim (rodando) ou o restante (pausado), nunca os dois.
    struct Salvo: Codable, Equatable, Sendable {
        var modo: Modo
        var fim: Date?
        var restante: TimeInterval?
    }

    /// O que fazer com o estado salvo ao abrir o app.
    enum Restauro: Equatable, Sendable {
        case rodar(Modo, fim: Date)
        case pausado(Modo, restante: TimeInterval)
        /// Acabou com o app fechado, há pouco: publica o aviso de fim.
        case terminou(Modo)
        /// Nada salvo, lixo, ou fim antigo demais: só limpa.
        case nada
    }

    /// Rodando: quando chega a zero.
    private(set) var fim: Date?
    /// Pausado: quanto faltava na hora da pausa.
    private(set) var restantePausado: TimeInterval?
    private(set) var modo: Modo = .livre

    var ativo: Bool { fim != nil || restantePausado != nil }
    var pausado: Bool { restantePausado != nil }

    /// Os Ajustes do timer. O Stepper já limita a faixa; o que vem do disco passa pelas regras ao ler.
    var minutosFoco: Int { didSet { padroes.set(minutosFoco, forKey: Self.chaveFoco) } }
    var minutosPausa: Int { didSet { padroes.set(minutosPausa, forKey: Self.chavePausa) } }
    var livres: [Int] { didSet { padroes.set(livres, forKey: Self.chaveLivres) } }
    /// Opt-in: roda os atalhos do Foco ao entrar e sair do foco do pomodoro.
    var naoPerturbe: Bool { didSet { padroes.set(naoPerturbe, forKey: Self.chaveNaoPerturbe) } }
    /// O que está no campo dos Ajustes antes do Enter. Mora aqui porque a view não tem `@State` (sem macros)
    /// e assim sobrevive a redesenhar a janela.
    var textoLivres: String

    var presets: [Preset] { Self.presets(foco: minutosFoco, pausa: minutosPausa, livres: livres) }

    private let mural: Mural
    /// Injetável: os testes usam uma suíte própria e não sujam os Ajustes do app.
    private let padroes: UserDefaults
    /// Uma só tarefa dormindo até o fim: pausar, parar ou reiniciar cancela a anterior, senão um timer velho avisaria.
    @ObservationIgnored private var vigia: Task<Void, Never>?
    /// O último estado de foco que passou pelos atalhos: só a troca roda um atalho, pausar o foco não desliga nada.
    @ObservationIgnored private(set) var emFoco = false
    /// Um atalho espera o anterior: parar e recomeçar o foco rápido não pode ligar antes de desligar.
    @ObservationIgnored private var filaDoFoco: Task<Void, Never>?

    init(mural: Mural, padroes: UserDefaults = .standard) {
        self.mural = mural
        self.padroes = padroes
        minutosFoco = Self.limitar(padroes.object(forKey: Self.chaveFoco) as? Int ?? Self.focoPadrao, a: Self.faixaFoco)
        minutosPausa = Self.limitar(padroes.object(forKey: Self.chavePausa) as? Int ?? Self.pausaPadrao, a: Self.faixaPausa)
        let livres = Self.limpar(padroes.array(forKey: Self.chaveLivres) as? [Int] ?? Self.livresPadrao)
        self.livres = livres
        textoLivres = Self.texto(livres: livres)
        naoPerturbe = padroes.bool(forKey: Self.chaveNaoPerturbe)
        restaurarEstado(agora: .now)
    }

    private func restaurarEstado(agora: Date) {
        let restauro = Self.restaurar(Self.decodificar(padroes.data(forKey: Self.chaveEstado)), agora: agora)
        switch restauro {
        case .rodar(let modo, let fim):
            self.modo = modo
            rodar(por: fim.timeIntervalSince(agora), agora: agora)
        case .pausado(let modo, let restante):
            self.modo = modo
            restantePausado = restante
        case .terminou(let modo):
            self.modo = modo
            emFoco = modo == .foco  // o foco acabou com o app fechado: o Não Perturbe ficou ligado, desliga
            terminar()  // publica o aviso e limpa o disco
        case .nada:
            padroes.removeObject(forKey: Self.chaveEstado)
        }
        if restauro != .nada { registro.info("timer restaurado do disco") }
    }

    /// Chamado a cada mudança de estado. Parado não deixa nada no disco.
    private func guardarEstado() {
        sincronizarFoco()
        let salvo: Salvo? = fim.map { Salvo(modo: modo, fim: $0) } ?? restantePausado.map { Salvo(modo: modo, restante: $0) }
        guard let dados = salvo.flatMap(Self.codificar) else {
            padroes.removeObject(forKey: Self.chaveEstado)
            return
        }
        padroes.set(dados, forKey: Self.chaveEstado)
    }

    /// Foco correndo ou pausado liga; terminar, parar ou trocar para pausa ou timer livre desliga.
    private func sincronizarFoco() {
        let foco = ativo && modo == .foco
        guard foco != emFoco else { return }
        emFoco = foco
        guard naoPerturbe else { return }
        let nome = foco ? Self.atalhoLigar : Self.atalhoDesligar
        let anterior = filaDoFoco
        filaDoFoco = Task { [mural] in
            await anterior?.value
            let status = await AtalhosApple.executar(nome)
            guard status != 0 else { return }
            registro.notice("timer: o atalho do Foco falhou (status \(status))")
            mural.receber(Atividade(id: "kizami-timer-foco", titulo: String(localized: "O Não Perturbe não mudou"),
                                    detalhe: String(localized: "Crie o atalho “\(nome)” no app Atalhos"),
                                    simbolo: "moon.zzz.fill", cor: "laranja", expira: 10, prioridade: "normal"))
        }
    }

    static func codificar(_ salvo: Salvo) -> Data? {
        try? JSONEncoder().encode(salvo)
    }

    /// Lixo ou modo desconhecido (o `Modo` não decodifica) viram nil.
    static func decodificar(_ dados: Data?) -> Salvo? {
        dados.flatMap { try? JSONDecoder().decode(Salvo.self, from: $0) }
    }

    /// Rodando com o fim no futuro volta a correr; pausado volta pausado; fim que passou avisa só se foi há pouco.
    static func restaurar(_ salvo: Salvo?, agora: Date) -> Restauro {
        switch (salvo?.modo, salvo?.fim, salvo?.restante) {
        case let (modo?, fim?, nil):
            let falta = fim.timeIntervalSince(agora)
            if falta > 0 { return falta <= maximoSalvo ? .rodar(modo, fim: fim) : .nada }
            return -falta <= janelaAvisoAtrasado ? .terminou(modo) : .nada
        case let (modo?, nil, restante?) where restante > 0 && restante <= maximoSalvo:
            return .pausado(modo, restante: restante)
        default:
            return .nada
        }
    }

    /// Confirma o campo dos Ajustes: guarda só o que passou nas regras e mostra no campo o que ficou.
    func aplicarTextoLivres() {
        let lidos = Self.livres(de: textoLivres)
        // "abc" + Enter não apaga os timers livres; só um campo vazio de propósito.
        guard !lidos.isEmpty || textoLivres.trimmingCharacters(in: .whitespaces).isEmpty else {
            textoLivres = Self.texto(livres: livres)
            return
        }
        livres = lidos
        textoLivres = Self.texto(livres: livres)
    }

    func iniciar(minutos: Int, modo: Modo, agora: Date = .now) {
        guard minutos > 0 else { return }
        mural.remover(id: Self.idAviso)  // o aviso do timer anterior já não vale
        self.modo = modo
        restantePausado = nil
        rodar(por: TimeInterval(minutos * 60), agora: agora)
        registro.info("timer iniciado (\(minutos) min)")
    }

    func pausar(agora: Date = .now) {
        guard let fim else { return }
        // Já passou da hora (o Mac acordou antes da tarefa rodar): pausar em 0:00 engoliria o aviso e o próximo passo.
        if fim <= agora { terminar(); return }
        vigia?.cancel()
        restantePausado = max(fim.timeIntervalSince(agora), 0)
        self.fim = nil
        guardarEstado()
    }

    func continuar(agora: Date = .now) {
        guard let restante = restantePausado else { return }
        restantePausado = nil
        rodar(por: restante, agora: agora)
    }

    func parar() {
        vigia?.cancel()
        fim = nil
        restantePausado = nil
        guardarEstado()
    }

    func restante(agora: Date) -> TimeInterval {
        if let fim { return max(fim.timeIntervalSince(agora), 0) }
        return restantePausado ?? 0
    }

    /// A tarefa dorme a partir do mesmo `agora` do fim: nos testes, com datas explícitas, ela nunca acorda.
    private func rodar(por segundos: TimeInterval, agora: Date) {
        vigia?.cancel()
        fim = agora.addingTimeInterval(segundos)
        guardarEstado()
        vigia = Task { [weak self] in
            // Task.sleep(for:) usa o ContinuousClock, que conta o tempo com o Mac dormindo, como o `fim` em Date.
            try? await Task.sleep(for: .seconds(segundos))
            guard !Task.isCancelled else { return }
            self?.terminar()
        }
    }

    /// Chegou a zero: avisa na ilha e, no pomodoro, o clique no aviso começa o próximo passo.
    func terminar() {
        // ponytail: o fim é só visual (o aviso na ilha), sem som. Para tocar um, chamar NSSound(named: "Glass")?.play() aqui.
        vigia?.cancel()
        fim = nil
        restantePausado = nil
        guardarEstado()
        let proximo = Self.proximo(depois: modo, foco: minutosFoco, pausa: minutosPausa)
        let aviso = Atividade(id: Self.idAviso, titulo: Self.titulo(modo), detalhe: proximo.map(Self.convite),
                              simbolo: modo == .foco ? "checkmark.circle.fill" : "timer", cor: modo.cor,
                              expira: Self.expiraAviso, prioridade: "alta")
        if proximo != nil {
            // Os minutos saem na hora do clique: mudar os Ajustes com o aviso na ilha já vale para o próximo passo.
            mural.receber(aviso) { [weak self, modo] in
                guard let self, let proximo = Self.proximo(depois: modo, foco: minutosFoco, pausa: minutosPausa) else { return }
                iniciar(minutos: proximo.minutos, modo: proximo.modo)
            }
        } else {
            mural.receber(aviso)
        }
        registro.info("timer terminou")
    }

    private static func titulo(_ modo: Modo) -> String {
        switch modo {
        case .foco: String(localized: "Foco concluído")
        case .pausa: String(localized: "Pausa acabou")
        case .livre: String(localized: "Timer acabou")
        }
    }

    private static func convite(_ proximo: Preset) -> String {
        proximo.modo == .pausa ? String(localized: "Clique para começar a pausa") : String(localized: "Clique para voltar ao foco")
    }

    /// O passo seguinte do pomodoro, com os minutos dos Ajustes; o timer livre não tem.
    static func proximo(depois modo: Modo, foco: Int, pausa: Int) -> Preset? {
        switch modo {
        case .foco: Preset(minutos: pausa, modo: .pausa)
        case .pausa: Preset(minutos: foco, modo: .foco)
        case .livre: nil
        }
    }

    /// Os botões da aba: foco, pausa e os livres, nessa ordem.
    static func presets(foco: Int, pausa: Int, livres: [Int]) -> [Preset] {
        [Preset(minutos: limitar(foco, a: faixaFoco), modo: .foco), Preset(minutos: limitar(pausa, a: faixaPausa), modo: .pausa)]
            + limpar(livres).map { Preset(minutos: $0, modo: .livre) }
    }

    /// "10, 15 50" → [10, 15, 50]. Vírgula ou espaço separam; lixo, fora da faixa e repetidos saem; a ordem fica.
    static func livres(de texto: String) -> [Int] {
        limpar(texto.split { $0 == "," || $0.isWhitespace }.compactMap { Int($0) })
    }

    /// Só os minutos na faixa, sem repetir, no máximo três.
    static func limpar(_ minutos: [Int]) -> [Int] {
        var vistos = Set<Int>()
        return Array(minutos.filter { faixaLivre.contains($0) && vistos.insert($0).inserted }.prefix(maxLivres))
    }

    static func texto(livres: [Int]) -> String {
        livres.map(String.init).joined(separator: ", ")
    }

    private static func limitar(_ valor: Int, a faixa: ClosedRange<Int>) -> Int {
        min(max(valor, faixa.lowerBound), faixa.upperBound)
    }

    /// "4:59", "25:00", "1:02:03". Arredonda para cima: com 0,4 s faltando mostra "0:01", e "0:00" só no fim.
    static func texto(_ restante: TimeInterval) -> String {
        let total = restante.isFinite ? Int(max(restante, 0).rounded(.up)) : 0
        let (horas, minutos, segundos) = (total / 3600, total / 60 % 60, total % 60)
        let ss = segundos < 10 ? "0\(segundos)" : "\(segundos)"
        if horas > 0 { return "\(horas):\(minutos < 10 ? "0" : "")\(minutos):\(ss)" }
        return "\(minutos):\(ss)"
    }
}
