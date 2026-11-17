import AppKit
import Observation
import os

let registro = Logger(subsystem: "io.github.henriquebap.kizami", category: "kizami")

/// O que outro app ou script pediu para mostrar. Vem de qualquer processo do Mac:
/// é dado, só exibido (truncado e validado), nunca executado nem aberto.
struct Atividade: Codable, Equatable, Identifiable, Sendable {
    static let expiraPadrao: Double = 10
    static let cores: Set<String> = ["vermelho", "laranja", "amarelo", "verde", "azul", "roxo", "rosa", "cinza"]
    /// Da que menos pede atenção para a que mais pede. Texto, e não número, para quem escreve o JSON ou a linha de comando.
    static let prioridades = ["baixa", "normal", "alta", "urgente"]

    var id: String
    var titulo: String
    var detalhe: String?
    /// Nome de um SF Symbol.
    var simbolo: String?
    /// Uma das `cores`; fora delas, branco.
    var cor: String?
    /// Segundos até sumir sozinha; 0 = fica até `remover`. Sem valor, `expiraPadrao`.
    var expira: Double?
    /// Uma das `prioridades`; fora delas, "normal". Ordena a ilha e decide quem desce como aviso.
    var prioridade: String?
    /// Preenchida pelo `Mural` ao receber; não viaja na mensagem.
    var chegada: Date?

    private enum CodingKeys: String, CodingKey { case id, titulo, detalhe, simbolo, cor, expira, prioridade }

    init(id: String, titulo: String, detalhe: String? = nil, simbolo: String? = nil, cor: String? = nil, expira: Double? = nil,
         prioridade: String? = nil) {
        self.id = id
        self.titulo = titulo
        self.detalhe = detalhe
        self.simbolo = simbolo
        self.cor = cor
        self.expira = expira
        self.prioridade = prioridade
    }

    /// 0 (baixa) a 3 (urgente).
    var peso: Int { Self.prioridades.firstIndex(of: prioridade ?? "") ?? 1 }

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
                         expira: min(max(expira, 0), 3600),
                         prioridade: bruta.prioridade.flatMap { prioridades.contains($0) ? $0 : nil })
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

/// As atividades na ilha, a que mais pede atenção primeiro (`Mural.antes`).
@MainActor @Observable
final class Mural {
    static let maximo = 8
    private(set) var atividades: [Atividade] = []
    /// Um prazo por atividade na ilha: reenviar, remover ou empurrar para fora da lista cancela o antigo,
    /// para uma enxurrada de mensagens não acumular tarefas dormindo.
    @ObservationIgnored private var prazos: [String: Task<Void, Never>] = [:]
    /// O que um clique na atividade abre. Só as fontes do próprio Kizami (Claude, agenda, interesses, Dock) dão uma:
    /// o que chega de fora é dado e nunca abre nada (AGENTS, regra 1).
    @ObservationIgnored private var acoes: [String: @MainActor () -> Void] = [:]

    /// As que acabaram de chegar, até `maximoAvisos`: a ilha desce com uma linha para cada por `tempoDeAviso`
    /// e depois volta a fechar. Chegando outra no meio, ela entra na pilha e o prazo recomeça.
    private(set) var avisos: [Atividade] = []
    static let maximoAvisos = 3
    static let tempoDeAviso: Duration = .seconds(3.5)
    @ObservationIgnored private var fimDoAviso: Task<Void, Never>?

    /// As que aparecem nas asas da ilha fechada, até três.
    var destaques: ArraySlice<Atividade> { atividades.prefix(Self.maximoAvisos) }

    /// A ordem da ilha: quem vem antes na lista, nas asas e na pilha de avisos.
    static func antes(_ a: Atividade, _ b: Atividade) -> Bool {
        if a.peso != b.peso { return a.peso > b.peso }
        return (a.chegada ?? .distantPast) > (b.chegada ?? .distantPast)
    }

    func receber(_ bruta: Atividade, aoAbrir acao: (@MainActor () -> Void)? = nil) {
        guard var atividade = Atividade.validar(bruta) else {
            registro.notice("atividade descartada: sem título ou id")
            return
        }
        atividade.chegada = .now
        prazos.removeValue(forKey: atividade.id)?.cancel()
        // Ordenar antes de cortar: com a ilha cheia, sai a menos importante, nunca um "precisa de você".
        trocar(por: Array(([atividade] + atividades.filter { $0.id != atividade.id }).sorted(by: Self.antes).prefix(Self.maximo)))
        registro.info("atividade recebida (\(self.atividades.count) na ilha)")
        acoes[atividade.id] = atividades.contains(where: { $0.id == atividade.id }) ? acao : nil
        avisar(atividade)
        // Cortada pela ilha cheia, não ganha prazo: ninguém cancelaria a tarefa dormindo.
        if let segundos = atividade.expira, segundos > 0, atividades.contains(where: { $0.id == atividade.id }) {
            prazos[atividade.id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(segundos))
                guard !Task.isCancelled else { return }
                self?.remover(id: atividade.id)
            }
        }
    }

    func podeAbrir(_ id: String) -> Bool { acoes[id] != nil }

    /// Clicou: abre a origem (a sessão do Claude, o jogo, a reunião, o app) e tira a atividade, como uma notificação.
    func abrir(_ id: String) {
        guard let acao = acoes[id] else { return }
        remover(id: id)
        acao()
    }

    func remover(id: String) {
        trocar(por: atividades.filter { $0.id != id })
    }

    func limpar() {
        trocar(por: [])
    }

    /// Troca a lista e cancela o prazo (e o aviso) de quem saiu dela.
    private func trocar(por novas: [Atividade]) {
        atividades = novas
        let ficam = Set(novas.map(\.id))
        for (id, prazo) in prazos where !ficam.contains(id) { prazo.cancel() }
        prazos = prazos.filter { ficam.contains($0.key) }
        acoes = acoes.filter { ficam.contains($0.key) }
        avisos = avisos.filter { ficam.contains($0.id) }
        if avisos.isEmpty { fimDoAviso?.cancel() }
    }

    /// Baixa prioridade não desce: entra na lista e nas asas em silêncio.
    private func avisar(_ atividade: Atividade) {
        guard atividade.peso > 0, atividades.contains(where: { $0.id == atividade.id }) else { return }
        let novos = Array(([atividade] + avisos.filter { $0.id != atividade.id }).sorted(by: Self.antes).prefix(Self.maximoAvisos))
        // Fora da pilha (três mais importantes já na tela), não estica o aviso: a ilha voltaria a fechar nunca.
        guard novos.contains(where: { $0.id == atividade.id }) else { return }
        fimDoAviso?.cancel()
        avisos = novos
        fimDoAviso = Task { [weak self] in
            try? await Task.sleep(for: Self.tempoDeAviso)
            guard !Task.isCancelled else { return }
            self?.encerrarAviso()
        }
    }

    /// Também chamado quando o cursor abre a ilha: a lista já mostra tudo, o aviso não volta depois.
    func encerrarAviso() {
        fimDoAviso?.cancel()
        avisos = []
    }
}
