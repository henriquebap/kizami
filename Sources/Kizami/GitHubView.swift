import SwiftUI

/// A seção dos Ajustes: liga os alertas do GitHub e mostra se o `gh` está respondendo.
struct AjustesGitHub: View {
    let github: GitHub

    init(github: GitHub) {
        self.github = github
    }

    var body: some View {
        Section("GitHub") {
            Toggle("Avisar quando a CI falhar ou pedirem minha revisão",
                   isOn: Binding(get: { github.ligado }, set: { github.ligado = $0 }))
            if github.ligado {
                situacao.font(.caption)
            }
            Text("Usa o gh que já está logado neste Mac, só lê e consulta a cada 5 minutos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var situacao: some View {
        switch github.situacao {
        case .desligado, .consultando:
            Text("Consultando o GitHub…").foregroundStyle(.secondary)
        case .semGh:
            Text("O gh não foi encontrado. Instale com o Homebrew (brew install gh) e faça login.").foregroundStyle(.orange)
        case .deslogado:
            Text("O gh não está logado. Rode gh auth login no Terminal.").foregroundStyle(.orange)
        case .semRede:
            Text("Sem resposta do GitHub agora. Tentando de novo.").foregroundStyle(.orange)
        case let .funcionando(prs, revisoes):
            Text("Funcionando: \(prs) PRs abertos, \(revisoes) revisões pedidas.").foregroundStyle(.secondary)
        }
    }
}
