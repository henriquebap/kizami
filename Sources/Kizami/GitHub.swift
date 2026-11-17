import AppKit
import Observation

/// Alertas do GitHub: CI que falhou num PR da pessoa e revisão pedida a ela. Chega lá pela CLI `gh` que ela já
/// tem logada: o Kizami nunca vê nem guarda token, e só lê (uma consulta GraphQL fixa).
@MainActor @Observable
final class GitHub {
    static let chaveLigado = "github.ligado"
    static let chaveVistos = "github.vistos"
    private static let intervalo: Duration = .seconds(5 * 60)

    enum Situacao: Equatable, Sendable {
        case desligado, consultando, semGh, deslogado, semRede
        case funcionando(prs: Int, revisoes: Int)
    }

    /// Desligado por padrão: só liga nos Ajustes. O `UserDefaults` guarda só este booleano e os ids já avisados.
    var ligado = false {
        didSet {
            guard ligado != oldValue, !restaurando else { return }
            UserDefaults.standard.set(ligado, forKey: Self.chaveLigado)
            // Religar é começar de novo: a primeira consulta só marca o que já existe (`novos`).
            vistos = nil
            UserDefaults.standard.removeObject(forKey: Self.chaveVistos)
            ligado ? agendar() : desligar()
        }
    }
    private(set) var situacao: Situacao = .desligado

    @ObservationIgnored private let mural: Mural
    /// nil = ainda não houve consulta desde que ligou.
    @ObservationIgnored private var vistos: Set<String>?
    @ObservationIgnored private var ciclo: Task<Void, Never>?
    /// Ligando pelo valor guardado, no `iniciar`: sem os efeitos de quem acabou de ligar no Toggle.
    @ObservationIgnored private var restaurando = false

    init(mural: Mural) {
        self.mural = mural
    }

    func iniciar() {
        guard ciclo == nil, UserDefaults.standard.bool(forKey: Self.chaveLigado) else { return }
        // Reiniciar o app não é religar: os vistos voltam do UserDefaults, e uma CI que falhou com o app fechado
        // ainda avisa na primeira consulta.
        vistos = UserDefaults.standard.stringArray(forKey: Self.chaveVistos).map(Set.init)
        restaurando = true
        ligado = true
        restaurando = false
        agendar()
    }

    private func desligar() {
        ciclo?.cancel()
        ciclo = nil
        situacao = .desligado
    }

    private func agendar() {
        ciclo?.cancel()
        situacao = .consultando
        ciclo = Task { [weak self] in
            var tentativas = 0
            while !Task.isCancelled {
                guard let self else { return }
                // Sem `gh`, deslogado ou sem rede: tenta de novo mais cedo e vai espaçando, até meia hora.
                let espera: Duration
                if await self.atualizar() {
                    tentativas = 0
                    espera = GitHub.intervalo
                } else {
                    espera = .seconds(min(60 * (1 << min(tentativas, 5)), 1800))
                    tentativas += 1
                }
                try? await Task.sleep(for: espera)
            }
        }
    }

    /// true quando a consulta respondeu.
    private func atualizar() async -> Bool {
        guard let gh = Self.localizar(existe: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            registro.notice("github: gh não encontrado")
            situacao = .semGh
            return false
        }
        let inicio = ContinuousClock.now
        let resposta = await Self.consultar(gh)
        guard ligado, !Task.isCancelled else { return true }  // desligou enquanto a resposta vinha
        switch resposta {
        case .deslogado:
            registro.notice("github: gh sem login")
            situacao = .deslogado
            return false
        case .falhou(let status):
            registro.notice("github: consulta falhou (status \(status))")
            situacao = .semRede
            return false
        case .dados(let dados):
            guard let resumo = Self.ler(dados) else {
                registro.notice("github: resposta ilegível (\(dados.count) bytes)")
                situacao = .semRede
                return false
            }
            let (avisos, novosVistos) = Self.novos(resumo, vistos: vistos)
            vistos = novosVistos
            UserDefaults.standard.set(Array(novosVistos), forKey: Self.chaveVistos)
            situacao = .funcionando(prs: resumo.meus.count, revisoes: resumo.revisoes.count)
            for aviso in avisos { publicar(aviso) }
            registro.info("github: \(resumo.meus.count) PRs, \(resumo.revisoes.count) revisões, \(avisos.count) avisos (\(ContinuousClock.now - inicio, privacy: .public))")
            return true
        }
    }

    private func publicar(_ aviso: Aviso) {
        let pr = aviso.pr
        let referencia = "\(pr.repo)#\(pr.numero)"
        let atividade = switch aviso.tipo {
        case .ciFalhou:
            Atividade(id: "github-ci-\(pr.id)", titulo: String(localized: "CI falhou"), detalhe: referencia,
                      simbolo: "xmark.octagon.fill", cor: "vermelho", expira: 30 * 60, prioridade: "alta")
        case .revisao:
            Atividade(id: "github-revisao-\(pr.id)", titulo: String(localized: "Revisão pedida"),
                      detalhe: "\(referencia) · \(pr.titulo)", simbolo: "eye.fill", cor: "roxo", expira: 30 * 60,
                      prioridade: "normal")
        }
        // A URL já passou por `link` no `ler`: sem ela, a atividade não abre nada.
        guard let url = pr.url else { return mural.receber(atividade) }
        mural.receber(atividade) { NSWorkspace.shared.open(url) }
    }
}

// MARK: Regras puras

extension GitHub {
    struct PR: Equatable, Sendable {
        /// O id de nó do GitHub (opaco): é ele, com o sha, que fica guardado nos vistos. Nunca o título nem o repo.
        var id: String
        var numero: Int
        var titulo: String
        /// Só o nome, sem o dono: cabe na linha da ilha.
        var repo: String
        var url: URL?
        var sha: String?
        /// O `statusCheckRollup.state` do último commit: SUCCESS, FAILURE, ERROR, PENDING, EXPECTED; nil sem CI.
        var ci: String?

        var ciFalhou: Bool { ci == "FAILURE" || ci == "ERROR" }
    }

    struct Resumo: Equatable, Sendable {
        var meus: [PR]
        var revisoes: [PR]
    }

    struct Aviso: Equatable, Sendable {
        enum Tipo: Equatable, Sendable { case ciFalhou, revisao }
        var tipo: Tipo
        var pr: PR
    }

    /// Conferida com `gh api graphql` (17/11/2026). Fixa: nada de fora entra nela.
    /// O `orderBy` importa: sem ele, `first: 20` traz os PRs mais antigos de quem tem muitos abertos.
    nonisolated static let consulta = """
        query { viewer { pullRequests(states: OPEN, first: 20, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes {
        id number title url repository { nameWithOwner } commits(last: 1) { nodes { commit { oid statusCheckRollup { state } } } } } } }
        search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE, first: 20) { nodes {
        ... on PullRequest { id number title url repository { nameWithOwner } } } } }
        """

    /// Onde o Homebrew instala o `gh` (Apple Silicon e Intel). Aberto pelo Finder, o app não tem o PATH do shell.
    static let caminhos = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    static func localizar(existe: (String) -> Bool) -> URL? {
        caminhos.first(where: existe).map { URL(fileURLWithPath: $0) }
    }

    /// O link do PR, só se for https em github.com exato: é a única coisa que um clique abre.
    static func link(_ texto: String) -> URL? {
        guard texto.count <= 300, let url = URL(string: texto), url.scheme == "https", url.host() == "github.com",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }

    private struct Resposta: Decodable {
        struct No: Decodable {
            struct Repo: Decodable { let nameWithOwner: String? }
            struct Commits: Decodable {
                struct NoCommit: Decodable {
                    struct Commit: Decodable {
                        struct Rollup: Decodable { let state: String? }
                        let oid: String?
                        let statusCheckRollup: Rollup?
                    }
                    let commit: Commit?
                }
                let nodes: [NoCommit?]?
            }
            let id: String?
            let number: Int?
            let title: String?
            let url: String?
            let repository: Repo?
            let commits: Commits?
        }
        struct Lista: Decodable { let nodes: [No?]? }
        struct Dados: Decodable {
            struct Viewer: Decodable { let pullRequests: Lista? }
            let viewer: Viewer?
            let search: Lista?
        }
        let data: Dados?
    }

    /// A resposta da consulta, ou nil se não é ela. Texto do GitHub é dado de fora: limpo como o de uma `Atividade`.
    static func ler(_ dados: Data) -> Resumo? {
        guard let resposta = try? JSONDecoder().decode(Resposta.self, from: dados), let d = resposta.data,
              let meus = d.viewer?.pullRequests?.nodes else { return nil }
        return Resumo(meus: Array(meus.compactMap(pr).prefix(20)),
                      revisoes: Array((d.search?.nodes ?? []).compactMap(pr).prefix(20)))
    }

    private static func pr(_ no: Resposta.No?) -> PR? {
        // Na busca, um resultado que não é PR vem como `{}`: sem id nem número, fica de fora.
        guard let no, let id = no.id, idValido(id), let numero = no.number, numero > 0,
              let completo = no.repository?.nameWithOwner else { return nil }
        let repo = Atividade.limpo(String(completo.split(separator: "/").last ?? ""), ate: 60)
        guard !repo.isEmpty else { return nil }
        let commit = no.commits?.nodes?.last??.commit
        return PR(id: id, numero: numero, titulo: Atividade.limpo(no.title ?? "", ate: 120), repo: repo,
                  url: no.url.flatMap(link), sha: commit?.oid.flatMap { idValido($0) ? $0 : nil },
                  ci: commit?.statusCheckRollup?.state)
    }

    /// Ids e shas vão para o id da atividade e para o UserDefaults: só ASCII simples e curto.
    private static func idValido(_ texto: String) -> Bool {
        !texto.isEmpty && texto.count <= 64 && texto.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// Os avisos novos e os vistos que passam a valer. Os vistos são só os fatos de agora (CI vermelha neste sha,
    /// revisão pedida): o que deixou de valer sai, e por isso a lista não cresce, e uma revisão pedida de novo avisa de novo.
    /// Primeira consulta depois de ligar (`vistos` nil): marca tudo e não avisa nada. A pessoa acabou de ligar e
    /// vê a contagem nos Ajustes; despejar uma CI vermelha de dias atrás e a fila de revisões seria barulho, não notícia.
    static func novos(_ resumo: Resumo, vistos: Set<String>?) -> ([Aviso], Set<String>) {
        let atuais = resumo.meus.compactMap { pr -> (String, Aviso)? in
            guard pr.ciFalhou else { return nil }
            return ("ci-\(pr.id)-\(pr.sha ?? "")", Aviso(tipo: .ciFalhou, pr: pr))
        } + resumo.revisoes.map { ("revisao-\($0.id)", Aviso(tipo: .revisao, pr: $0)) }
        let chaves = Set(atuais.map(\.0))
        guard let vistos else { return ([], chaves) }
        return (atuais.filter { !vistos.contains($0.0) }.map(\.1), chaves)
    }
}

// MARK: O processo

extension GitHub {
    enum Saida: Equatable, Sendable {
        case dados(Data)
        case deslogado
        case falhou(Int32)
    }

    private nonisolated static let limite: TimeInterval = 20
    /// 40 PRs com títulos longos dão ~15 KB; muito além disso não é a nossa consulta.
    nonisolated static let tamanhoMaximo = 1_000_000

    /// Roda o `gh` com argumentos fixos, fora da thread principal, com `limite` e `tamanhoMaximo`.
    nonisolated static func consultar(_ gh: URL) async -> Saida {
        await withCheckedContinuation { continuacao in
            DispatchQueue.global(qos: .utility).async {
                continuacao.resume(returning: rodar(gh))
            }
        }
    }

    private nonisolated static func rodar(_ gh: URL) -> Saida {
        let processo = Process()
        processo.executableURL = gh
        processo.arguments = ["api", "graphql", "-f", "query=\(consulta)"]
        var ambiente = ProcessInfo.processInfo.environment
        // Nunca esperar resposta da pessoa num terminal que não existe, nem gastar a consulta com aviso de versão.
        ambiente["GH_PROMPT_DISABLED"] = "1"
        ambiente["GH_NO_UPDATE_NOTIFIER"] = "1"
        ambiente["NO_COLOR"] = "1"
        // Sempre o github.com: um GH_HOST de Enterprise no ambiente levaria a consulta a um host não combinado
        // (e os links nem abririam, `link` só aceita github.com).
        ambiente["GH_HOST"] = "github.com"
        for chave in ["GH_REPO", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"] { ambiente[chave] = nil }
        processo.environment = ambiente
        let saida = Pipe()
        let erro = Pipe()
        processo.standardOutput = saida
        processo.standardError = erro
        processo.standardInput = FileHandle.nullDevice
        do {
            try processo.run()
        } catch {
            return .falhou(-1)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + limite) {
            if processo.isRunning { processo.terminate() }
        }
        // Lê enquanto roda: esperar o fim antes de ler trava o `gh` quando a saída passa do buffer do pipe (64 KB).
        let dados = (try? saida.fileHandleForReading.read(upToCount: tamanhoMaximo + 1)) ?? Data()
        if dados.count > tamanhoMaximo, processo.isRunning { processo.terminate() }
        let mensagem = (try? erro.fileHandleForReading.read(upToCount: 4096)) ?? Data()
        processo.waitUntilExit()
        let status = processo.terminationStatus
        // 4 é o código do `gh` para "precisa de login"; token revogado responde 401 com status 1.
        // A mensagem de erro só é olhada aqui, nunca vai para o log.
        if status == 4 || String(decoding: mensagem, as: UTF8.self).contains("HTTP 401") { return .deslogado }
        guard status == 0, processo.terminationReason == .exit, dados.count <= tamanhoMaximo else { return .falhou(status) }
        return .dados(dados)
    }
}
