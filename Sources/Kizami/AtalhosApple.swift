import Foundation
import Observation

/// Os atalhos do app Atalhos (Shortcuts) que a pessoa escolheu nos Ajustes, como botões na aba Atalhos da ilha.
/// Tudo passa pelo `/usr/bin/shortcuts` do próprio macOS: `list` para saber quais existem e `run` para rodar um.
/// O nome do atalho é dado da pessoa: vai ao processo como um argumento só, nunca por shell, e nunca ao log.
@MainActor @Observable
final class AtalhosApple {
    static let chaveEscolhidos = "atalhosApple.escolhidos"
    /// Seis cabem numa fileira da ilha sem rolar demais.
    static let maximo = 6

    /// Os atalhos da pessoa, na ordem da `shortcuts list`.
    private(set) var disponiveis: [String] = []
    /// Já houve uma leitura (respondendo ou não): antes dela os Ajustes esperam em vez de dizer "não deu para conferir".
    private(set) var leu = false
    /// A última leitura não respondeu: os Ajustes avisam em vez de mostrar uma lista vazia como se fosse real.
    private(set) var leituraFalhou = false
    /// A ordem é a dos botões na ilha. O `UserDefaults` guarda só esta lista de nomes.
    var escolhidos: [String] {
        didSet { UserDefaults.standard.set(Self.conciliar(escolhidos, disponiveis: nil), forKey: Self.chaveEscolhidos) }
    }

    @ObservationIgnored private let mural: Mural

    init(mural: Mural) {
        self.mural = mural
        escolhidos = Self.conciliar(UserDefaults.standard.stringArray(forKey: Self.chaveEscolhidos) ?? [], disponiveis: nil)
    }

    /// Relê a lista. Só uma leitura que respondeu tira dos escolhidos o que deixou de existir: um `shortcuts`
    /// travado ou lento não pode apagar a escolha da pessoa.
    func recarregar() async {
        let inicio = ContinuousClock.now
        defer { leu = true }
        guard let saida = await Self.listar() else {
            leituraFalhou = true
            registro.notice("atalhos da Apple: a lista não respondeu")
            return
        }
        leituraFalhou = false
        disponiveis = Self.ler(saida)
        // Lista vazia (o app Atalhos ainda sincronizando depois do login) ou cortada no teto: não é a lista inteira,
        // então não poda a escolha da pessoa.
        let completa = !disponiveis.isEmpty && disponiveis.count < Self.maximoNaLista
        let conciliados = completa ? Self.conciliar(escolhidos, disponiveis: disponiveis) : escolhidos
        if conciliados != escolhidos { escolhidos = conciliados }
        registro.info("atalhos da Apple: \(self.disponiveis.count) na lista, \(self.escolhidos.count) escolhidos (\(ContinuousClock.now - inicio, privacy: .public))")
    }

    /// Para os Ajustes do Timer: o atalho está na lista (true), não está (false) ou não dá para saber (nil): a lista
    /// não respondeu, veio vazia (o app Atalhos sincronizando) ou cortada no teto.
    func existe(_ nome: String) -> Bool? {
        Self.existe(nome, disponiveis: disponiveis, leituraFalhou: leituraFalhou)
    }

    static func existe(_ nome: String, disponiveis: [String], leituraFalhou: Bool) -> Bool? {
        if disponiveis.contains(nome) { return true }
        return leituraFalhou || disponiveis.isEmpty || disponiveis.count >= maximoNaLista ? nil : false
    }

    /// Roda um escolhido. Relê a lista antes (leva ~15 ms) para só rodar o que existe agora no app Atalhos.
    /// Sem prazo: um atalho pode demorar ou esperar a pessoa responder um diálogo dele.
    func rodar(_ nome: String) {
        guard escolhidos.contains(nome) else { return }
        Task {
            await recarregar()
            let inicio = ContinuousClock.now
            // Sumiu do app Atalhos: o `recarregar` já tirou dos escolhidos, e o clique não fica sem resposta.
            // Lista que não respondeu: roda assim mesmo, e o próprio `shortcuts run` diz se o atalho existe.
            let incompleta = leituraFalhou || disponiveis.isEmpty || disponiveis.count >= Self.maximoNaLista
            let status = disponiveis.contains(nome) || incompleta ? await Self.executar(nome) : -1
            guard status != 0 else {
                registro.info("atalhos da Apple: atalho rodou (\(ContinuousClock.now - inicio, privacy: .public))")
                return
            }
            registro.notice("atalhos da Apple: atalho falhou (status \(status))")
            mural.receber(Atividade(id: "kizami-atalho-apple", titulo: String(localized: "O atalho falhou"),
                                    detalhe: nome, simbolo: "square.stack.3d.up.slash.fill", cor: "laranja",
                                    expira: 8, prioridade: "normal"))
        }
    }

    func alternar(_ nome: String) {
        escolhidos = Self.alternado(escolhidos, nome)
    }

    /// Sobe o escolhido uma posição: com seis no máximo, é o bastante para pôr qualquer um em primeiro.
    func subir(_ nome: String) {
        escolhidos = Self.subido(escolhidos, nome)
    }
}

// MARK: Regras puras

extension AtalhosApple {
    /// Muito acima de qualquer coleção real; só protege a tela dos Ajustes de uma saída que não é a nossa.
    static let maximoNaLista = 500

    /// Uma linha por atalho. Espaço nas pontas e `\r` saem; linha vazia e nome repetido também
    /// (dois atalhos com o mesmo nome seriam o mesmo botão: `run` pelo nome roda um só).
    // ponytail: um nome que começa ou termina em espaço perde o espaço e o `run` não o acha (vira o aviso de falha).
    // Se aparecer, listar com `--show-identifiers` e rodar pelo identificador.
    static func ler(_ saida: String) -> [String] {
        var vistos = Set<String>()
        return Array(saida.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && vistos.insert($0).inserted }
            .prefix(maximoNaLista))
    }

    /// Os escolhidos que valem: sem vazio nem repetido, na ordem da pessoa, até `maximo`. Com a lista lida
    /// (`disponiveis` não nil), só os que ainda existem nela.
    static func conciliar(_ escolhidos: [String], disponiveis: [String]?) -> [String] {
        let existem = disponiveis.map(Set.init)
        var vistos = Set<String>()
        return Array(escolhidos
            .filter { !$0.isEmpty && existem?.contains($0) != false && vistos.insert($0).inserted }
            .prefix(maximo))
    }

    /// Tira se já estava; põe no fim se ainda cabe.
    static func alternado(_ escolhidos: [String], _ nome: String) -> [String] {
        if escolhidos.contains(nome) { return escolhidos.filter { $0 != nome } }
        return escolhidos.count < maximo && !nome.isEmpty ? escolhidos + [nome] : escolhidos
    }

    static func subido(_ escolhidos: [String], _ nome: String) -> [String] {
        guard let i = escolhidos.firstIndex(of: nome), i > 0 else { return escolhidos }
        var nova = escolhidos
        nova.swapAt(i, i - 1)
        return nova
    }
}

// MARK: O processo

extension AtalhosApple {
    private nonisolated static let shortcuts = URL(fileURLWithPath: "/usr/bin/shortcuts")
    private nonisolated static let limiteDaLista: TimeInterval = 10
    /// 500 nomes longos dão uns 50 KB.
    nonisolated static let tamanhoMaximoDaLista = 256 * 1024

    /// A saída da `shortcuts list`, ou nil se não respondeu bem no prazo e no tamanho.
    nonisolated static func listar() async -> String? {
        await withCheckedContinuation { continuacao in
            DispatchQueue.global(qos: .utility).async {
                continuacao.resume(returning: listarAgora())
            }
        }
    }

    private nonisolated static func listarAgora() -> String? {
        let processo = Process()
        processo.executableURL = shortcuts
        processo.arguments = ["list"]
        let saida = Pipe()
        processo.standardOutput = saida
        processo.standardError = FileHandle.nullDevice
        processo.standardInput = FileHandle.nullDevice
        do {
            try processo.run()
        } catch {
            return nil
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + limiteDaLista) {
            if processo.isRunning { processo.terminate() }
        }
        // Lê enquanto roda: esperar o fim antes de ler trava o processo quando a saída passa do buffer do pipe.
        let dados = (try? saida.fileHandleForReading.read(upToCount: tamanhoMaximoDaLista + 1)) ?? Data()
        if dados.count > tamanhoMaximoDaLista, processo.isRunning { processo.terminate() }
        processo.waitUntilExit()
        guard processo.terminationReason == .exit, processo.terminationStatus == 0,
              dados.count <= tamanhoMaximoDaLista else { return nil }
        return String(decoding: dados, as: UTF8.self)
    }

    /// O `--` impede que um nome começando com hífen vire opção (`-h`, `--input-path`…). Conferido (17/11/2026):
    /// `shortcuts run -- -h-inexistente` responde "Couldn't find shortcut", ou seja, leu como nome.
    nonisolated static func argumentos(rodar nome: String) -> [String] { ["run", "--", nome] }

    /// Roda o atalho e devolve o status (-1 se nem começou ou morreu por sinal). Sem entrada e sem saída:
    /// nada da pessoa vai para o atalho além do nome, e nada dele volta além do status.
    nonisolated static func executar(_ nome: String) async -> Int32 {
        let processo = Process()
        processo.executableURL = shortcuts
        processo.arguments = argumentos(rodar: nome)
        processo.standardOutput = FileHandle.nullDevice
        processo.standardError = FileHandle.nullDevice
        processo.standardInput = FileHandle.nullDevice
        // `terminationHandler` em vez de `waitUntilExit`: um atalho longo não segura uma thread parada.
        return await withCheckedContinuation { continuacao in
            processo.terminationHandler = { fim in
                continuacao.resume(returning: fim.terminationReason == .exit ? fim.terminationStatus : -1)
            }
            do {
                try processo.run()
            } catch {
                processo.terminationHandler = nil
                continuacao.resume(returning: -1)
            }
        }
    }
}
