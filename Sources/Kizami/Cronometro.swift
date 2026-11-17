import Foundation
import Observation

/// O timer da ilha, com o pomodoro: foco de 25, pausa de 5, e o clique no aviso de fim começa o passo seguinte.
/// Guarda a hora do fim, não um contador: a contagem na tela sai de `restante(agora:)`, e dormir o Mac não a atrasa.
@MainActor @Observable
final class Cronometro {
    enum Modo: Equatable, Sendable {
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

    static let minutosFoco = 25
    static let minutosPausa = 5
    static let idAviso = "kizami-timer"
    /// O aviso de fim fica um pouco na ilha: dá tempo de voltar ao Mac e clicar para o próximo passo.
    static let expiraAviso: Double = 120

    /// Rodando: quando chega a zero.
    private(set) var fim: Date?
    /// Pausado: quanto faltava na hora da pausa.
    private(set) var restantePausado: TimeInterval?
    private(set) var modo: Modo = .livre

    var ativo: Bool { fim != nil || restantePausado != nil }
    var pausado: Bool { restantePausado != nil }

    private let mural: Mural
    /// Uma só tarefa dormindo até o fim: pausar, parar ou reiniciar cancela a anterior, senão um timer velho avisaria.
    @ObservationIgnored private var vigia: Task<Void, Never>?

    init(mural: Mural) {
        self.mural = mural
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
    }

    func restante(agora: Date) -> TimeInterval {
        if let fim { return max(fim.timeIntervalSince(agora), 0) }
        return restantePausado ?? 0
    }

    /// A tarefa dorme a partir do mesmo `agora` do fim: nos testes, com datas explícitas, ela nunca acorda.
    private func rodar(por segundos: TimeInterval, agora: Date) {
        vigia?.cancel()
        fim = agora.addingTimeInterval(segundos)
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
        let proximo = Self.proximo(depois: modo)
        let aviso = Atividade(id: Self.idAviso, titulo: Self.titulo(modo), detalhe: proximo.map(Self.convite),
                              simbolo: modo == .foco ? "checkmark.circle.fill" : "timer", cor: modo.cor,
                              expira: Self.expiraAviso, prioridade: "alta")
        if let proximo {
            mural.receber(aviso) { [weak self] in self?.iniciar(minutos: proximo.minutos, modo: proximo.modo) }
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

    private static func convite(_ proximo: (minutos: Int, modo: Modo)) -> String {
        proximo.modo == .pausa ? String(localized: "Clique para começar a pausa") : String(localized: "Clique para voltar ao foco")
    }

    /// O passo seguinte do pomodoro; o timer livre não tem.
    static func proximo(depois modo: Modo) -> (minutos: Int, modo: Modo)? {
        switch modo {
        case .foco: (minutosPausa, .pausa)
        case .pausa: (minutosFoco, .foco)
        case .livre: nil
        }
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
