import AppKit
import Observation
import os

let registro = Logger(subsystem: "io.github.henriquebap.kizami", category: "kizami")

/// O que outro app ou script pediu para mostrar. Vem de qualquer processo do Mac:
/// é dado, só exibido (truncado e validado), nunca executado nem aberto.
struct Atividade: Codable, Equatable, Identifiable, Sendable {
    static let expiraPadrao: Double = 10
    static let cores: Set<String> = ["vermelho", "laranja", "amarelo", "verde", "azul", "roxo", "rosa", "cinza"]

    var id: String
    var titulo: String
    var detalhe: String?
    /// Nome de um SF Symbol.
    var simbolo: String?
    /// Uma das `cores`; fora delas, branco.
    var cor: String?
    /// Segundos até sumir sozinha; 0 = fica até `remover`. Sem valor, `expiraPadrao`.
    var expira: Double?
    /// Preenchida pelo `Mural` ao receber; não viaja na mensagem.
    var chegada: Date?

    private enum CodingKeys: String, CodingKey { case id, titulo, detalhe, simbolo, cor, expira }

    init(id: String, titulo: String, detalhe: String? = nil, simbolo: String? = nil, cor: String? = nil, expira: Double? = nil) {
        self.id = id
        self.titulo = titulo
        self.detalhe = detalhe
        self.simbolo = simbolo
        self.cor = cor
        self.expira = expira
    }

    /// Devolve uma cópia pronta para a ilha, ou nil se não há o que mostrar.
    static func validar(_ bruta: Atividade) -> Atividade? {
        let titulo = limpo(bruta.titulo, ate: 60)
        guard !titulo.isEmpty, !bruta.id.isEmpty else { return nil }
        let simbolo = bruta.simbolo.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0 }
        let detalhe = bruta.detalhe.map { limpo($0, ate: 120) }
        let expira = bruta.expira.flatMap { $0.isFinite ? $0 : nil } ?? expiraPadrao  // NaN passaria pelo min/max
        return Atividade(id: String(bruta.id.unicodeScalars.prefix(64)),
                         titulo: titulo,
                         detalhe: detalhe?.isEmpty == false ? detalhe : nil,
                         simbolo: simbolo ?? "bell.fill",
                         cor: bruta.cor.flatMap { cores.contains($0) ? $0 : nil },
                         expira: min(max(expira, 0), 3600))
    }

    /// Texto de fora, pronto para uma linha da ilha:
    /// - sem caracteres de controle nem de formatação: largura zero deixaria a ilha em branco,
    ///   e os de direção (U+202E) inverteriam o título na tela. O U+200D fica, porque junta emojis;
    /// - cortado também por escalares: um só caractere com milhares de acentos (Zalgo) passaria pelo `prefix` de caracteres.
    static func limpo(_ texto: String, ate limite: Int) -> String {
        let escalares = texto.unicodeScalars.prefix(limite * 4).filter {
            $0 == "\u{200D}" || ![.control, .format].contains($0.properties.generalCategory)
        }
        return String(String(String.UnicodeScalarView(escalares))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(limite))
    }
}

/// As atividades na ilha, da mais recente para a mais antiga.
@MainActor @Observable
final class Mural {
    static let maximo = 8
    private(set) var atividades: [Atividade] = []
    /// Um prazo por atividade na ilha: reenviar, remover ou empurrar para fora da lista cancela o antigo,
    /// para uma enxurrada de mensagens não acumular tarefas dormindo.
    @ObservationIgnored private var prazos: [String: Task<Void, Never>] = [:]

    /// A que aparece na ilha fechada.
    var destaque: Atividade? { atividades.first }

    func receber(_ bruta: Atividade) {
        guard var atividade = Atividade.validar(bruta) else {
            registro.notice("atividade descartada: sem título ou id")
            return
        }
        atividade.chegada = .now
        prazos.removeValue(forKey: atividade.id)?.cancel()
        trocar(por: Array(([atividade] + atividades.filter { $0.id != atividade.id }).prefix(Self.maximo)))
        registro.info("atividade recebida (\(self.atividades.count) na ilha)")
        if let segundos = atividade.expira, segundos > 0 {
            prazos[atividade.id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(segundos))
                guard !Task.isCancelled else { return }
                self?.remover(id: atividade.id)
            }
        }
    }

    func remover(id: String) {
        trocar(por: atividades.filter { $0.id != id })
    }

    func limpar() {
        trocar(por: [])
    }

    /// Troca a lista e cancela o prazo de quem saiu dela.
    private func trocar(por novas: [Atividade]) {
        atividades = novas
        let ficam = Set(novas.map(\.id))
        for (id, prazo) in prazos where !ficam.contains(id) { prazo.cancel() }
        prazos = prazos.filter { ficam.contains($0.key) }
    }
}
