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
    let lembretes: Lembretes
    let fones: Fones
    let personalizacao: Personalizacao
    let atalhosApple: AtalhosApple
    let login: Login
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
            AjustesLembretes(lembretes: lembretes)
            Section("Fones") {
                Toggle("Avisar quando um fone Bluetooth conectar", isOn: Binding(get: { fones.ligado }, set: { fones.ligado = $0 }))
                Text("AirPods, Beats e outros fones: o nome e a bateria aparecem na ilha por alguns segundos. O macOS pede acesso ao Bluetooth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Geral") {
                Toggle("Abrir o Kizami no login", isOn: Binding(get: { login.ligado }, set: { login.alternar(para: $0) }))
                if login.precisaAprovar {
                    Text("O macOS pede a sua aprovação em Itens de Início.").font(.caption).foregroundStyle(.secondary)
                    Button("Abrir Itens de Início") { login.abrirItensDeInicio() }
                } else if login.falhou {
                    Text("Não deu para mudar. Abra o Kizami de /Applications e tente de novo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear { login.conferir() }
            // Voltando dos Ajustes do Sistema (Itens de Início), o estado pode ter mudado lá.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                login.conferir()
            }
            AjustesIlha(personalizacao: personalizacao)
            AjustesAtalhosApple(atalhos: atalhosApple)
            AjustesTimer(cronometro: Kizami.shared.cronometro, atalhos: atalhosApple)
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
