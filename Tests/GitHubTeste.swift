import Foundation

// GitHub: leitura da resposta do `gh api graphql` (forma real, nomes trocados), URL do clique, `gh` e os avisos novos.
@MainActor func testarGitHub() {
    // Resposta real (17/11/2026), recortada e com nomes fictícios: um PR com CI verde, um com CI vermelha,
    // um sem CI, e na busca uma revisão pedida e um resultado que não é PR (`{}`).
    let real = """
        {"data":{"viewer":{"pullRequests":{"nodes":[
        {"id":"PR_kwDOAAAAAA8AAAABAAAAAQ","number":2,"title":"v0.10: placar ao vivo e timer","url":"https://github.com/fulana/ilha/pull/2",
         "repository":{"nameWithOwner":"fulana/ilha"},"commits":{"nodes":[{"commit":{"oid":"61cfe9b4762eb59241ac40068f7c1e90b940d3f0","statusCheckRollup":{"state":"SUCCESS"}}}]}},
        {"id":"PR_kwDOAAAAAA8AAAABAAAAAg","number":28,"title":"fix: tira da oferta o que não se sustenta","url":"https://github.com/fulana/portfolio/pull/28",
         "repository":{"nameWithOwner":"fulana/portfolio"},"commits":{"nodes":[{"commit":{"oid":"0de97d086e4384ab427beeda449b9c98b00b2be4","statusCheckRollup":{"state":"FAILURE"}}}]}},
        {"id":"PR_kwDOAAAAAA8AAAABAAAAAw","number":3,"title":"docs","url":"https://github.com/fulana/site/pull/3",
         "repository":{"nameWithOwner":"fulana/site"},"commits":{"nodes":[{"commit":{"oid":"e8112d91893428b61b1dc0dcc85c8e2782ecffcf","statusCheckRollup":null}}]}}
        ]}},"search":{"nodes":[
        {"id":"PR_kwDOAAAAAA8AAAABAAAABA","number":7,"title":"feat: \\u202Eexportar CSV","url":"https://github.com/outra/app/pull/7",
         "repository":{"nameWithOwner":"outra/app"}},
        {}
        ]}}}
        """
    let resumo = GitHub.ler(Data(real.utf8))
    conferir("lê os PRs da pessoa", resumo?.meus.map(\.numero), [2, 28, 3])
    conferir("lê as revisões e pula o que não é PR", resumo?.revisoes.map(\.numero), [7])
    conferir("repo sem o dono", resumo?.meus.map(\.repo), ["ilha", "portfolio", "site"])
    conferir("estado da CI", resumo?.meus.map(\.ci), ["SUCCESS", "FAILURE", nil])
    conferir("sha do último commit", resumo?.meus[1].sha, "0de97d086e4384ab427beeda449b9c98b00b2be4")
    conferir("título limpo (sem U+202E)", resumo?.revisoes.first?.titulo, "feat: exportar CSV")
    conferir("URL do PR", resumo?.meus.first?.url?.absoluteString, "https://github.com/fulana/ilha/pull/2")

    conferir("lixo", GitHub.ler(Data("não é json".utf8)), nil)
    conferir("erro do GraphQL", GitHub.ler(Data(#"{"errors":[{"message":"Bad credentials"}]}"#.utf8)), nil)
    conferir("sem a lista de PRs", GitHub.ler(Data(#"{"data":{"viewer":{}}}"#.utf8)), nil)
    let idEstranho = #"{"data":{"viewer":{"pullRequests":{"nodes":[{"id":"a b\n","number":1,"repository":{"nameWithOwner":"x/y"}}]}}}}"#
    conferir("id com espaço fica de fora", GitHub.ler(Data(idEstranho.utf8))?.meus.count, 0)
    let urlDeFora = #"{"data":{"viewer":{"pullRequests":{"nodes":[{"id":"PR_1","number":1,"url":"https://evil.example/pull/1","repository":{"nameWithOwner":"x/y"}}]}}}}"#
    conferir("PR com URL de fora fica sem clique", GitHub.ler(Data(urlDeFora.utf8))?.meus.first?.url, nil)

    // MARK: URL do clique

    conferir("link do github", GitHub.link("https://github.com/a/b/pull/1")?.host(), "github.com")
    conferir("link http", GitHub.link("http://github.com/a/b/pull/1"), nil)
    conferir("link de outro host", GitHub.link("https://github.com.evil.example/a"), nil)
    conferir("link de subdomínio", GitHub.link("https://gist.github.com/a"), nil)
    conferir("link com usuário", GitHub.link("https://x@github.com/a"), nil)
    conferir("link com porta", GitHub.link("https://github.com:8443/a"), nil)
    conferir("link javascript", GitHub.link("javascript:alert(1)"), nil)

    // MARK: gh

    conferir("gh do Homebrew no Apple Silicon", GitHub.localizar { $0 == "/opt/homebrew/bin/gh" }?.path, "/opt/homebrew/bin/gh")
    conferir("gh do Homebrew no Intel", GitHub.localizar { $0 == "/usr/local/bin/gh" }?.path, "/usr/local/bin/gh")
    conferir("sem gh", GitHub.localizar { _ in false }, nil)

    // MARK: Avisos novos

    guard let resumo else { return }
    let (primeira, vistos) = GitHub.novos(resumo, vistos: nil)
    conferir("primeira consulta não despeja o passado", primeira.count, 0)
    conferir("primeira consulta marca o que existe", vistos.count, 2)
    conferir("a mesma resposta não avisa de novo", GitHub.novos(resumo, vistos: vistos).0.count, 0)

    var depois = resumo
    depois.revisoes.append(GitHub.PR(id: "PR_novo", numero: 9, titulo: "nova", repo: "app", url: nil, sha: nil, ci: nil))
    depois.meus[0].ci = "ERROR"
    let (avisos, vistos2) = GitHub.novos(depois, vistos: vistos)
    conferir("CI que quebrou e revisão nova", avisos.map(\.tipo), [.ciFalhou, .revisao])
    conferir("os avisos são dos PRs certos", avisos.map(\.pr.numero), [2, 9])

    var corrigido = depois
    corrigido.meus[1].sha = "1111111111111111111111111111111111111111"
    corrigido.meus[1].ci = "PENDING"
    let (_, vistos3) = GitHub.novos(corrigido, vistos: vistos2)
    conferir("CI vermelha antiga sai dos vistos", vistos3.contains("ci-PR_kwDOAAAAAA8AAAABAAAAAg-0de97d086e4384ab427beeda449b9c98b00b2be4"), false)
    var deNovo = corrigido
    deNovo.meus[1].ci = "FAILURE"
    let (deNovoAvisos, _) = GitHub.novos(deNovo, vistos: vistos3)
    conferir("CI que falha de novo com outro sha avisa", deNovoAvisos.map(\.pr.numero), [28])
    conferir("PENDING e SUCCESS não avisam", GitHub.novos(corrigido, vistos: vistos3).0.count, 0)
}
