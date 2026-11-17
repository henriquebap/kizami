import AppKit
import SwiftUI

/// O que a pessoa está digitando nos Ajustes. Classe observável porque o build não tem a macro `@State`.
@MainActor @Observable
final class FormularioAjustes {
    var cidade = ""
    var buscando = false
    var naoAchou = false
}

/// A janela de Ajustes: a cidade do tempo, o acesso à agenda e como ligar as sessões do Claude.
struct AjustesView: View {
    let tempo: Tempo
    let agenda: Agenda
    let mac: Mac
    let interesses: Interesses
    @Bindable var formulario: FormularioAjustes
    let formularioInteresses: FormularioInteresses
    let copiados: Copiados
    let downloads: Downloads
    let github: GitHub
    @AppStorage(Janela.chaveUrgenteEmTelaCheia) private var urgenteEmTelaCheia = false

    var body: some View {
        Form {
            Section("Tempo") {
                if let local = tempo.local {
                    LabeledContent("Cidade") { Text(verbatim: local) }  // verbatim: o nome vem da API
                }
                HStack {
                    TextField(tempo.local == nil ? "Cidade" : "Trocar de cidade", text: $formulario.cidade)
                        .onSubmit(buscar)
                    Button("Buscar", action: buscar)
                        .disabled(formulario.buscando || formulario.cidade.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if formulario.naoAchou {
                    Text("Não encontrei essa cidade, ou a rede falhou.").font(.caption).foregroundStyle(.secondary)
                }
                if tempo.local != nil {
                    Button("Esquecer a cidade") { tempo.esquecerCidade() }
                }
            }
            Section("Agenda") {
                switch agenda.acesso {
                case .permitido: Text("O próximo evento aparece na ilha, com um aviso 15 minutos antes.")
                case .naoPedido: Text("O Kizami pede acesso aos Calendários ao abrir.")
                case .negado:
                    Text("Sem acesso aos Calendários: libere o Kizami nos Ajustes do Sistema e abra esta janela de novo.")
                    Button("Abrir os Ajustes do Sistema") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            AjustesInteresses(interesses: interesses, formulario: formularioInteresses)
            AjustesMac(mac: mac)
            AjustesCopiados(copiados: copiados)
            AjustesDownloads(downloads: downloads)
            AjustesGitHub(github: github)
            Section("Tela cheia") {
                Toggle("Avisos urgentes por cima da tela cheia", isOn: $urgenteEmTelaCheia)
                Text("Em vídeo ou jogo em tela cheia, a ilha some. Ligado, ela volta só para o que é urgente: a reunião começando ou o Claude pedindo permissão.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Claude Code") {
                Text("As sessões aparecem na ilha quando os hooks do Claude Code chamam o Kizami (docs/CLAUDE-HOOKS.md).")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, idealWidth: 460, minHeight: 420, idealHeight: 640)
    }

    private func buscar() {
        let nome = formulario.cidade.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty, !formulario.buscando else { return }
        formulario.buscando = true
        formulario.naoAchou = false
        Task {
            let achou = await tempo.trocarCidade(nome)
            formulario.buscando = false
            formulario.naoAchou = !achou
            if achou { formulario.cidade = "" }
        }
    }
}
