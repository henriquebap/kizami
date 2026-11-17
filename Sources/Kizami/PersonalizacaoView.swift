import SwiftUI

/// A seção "Ilha" dos Ajustes: quais abas aparecem e em que ordem, o que o Início mostra e a vez de cada coisa
/// nas asas da ilha fechada. Ordem com setas em vez de arrastar: um `Form` agrupado não tem lista reordenável.
struct AjustesIlha: View {
    let personalizacao: Personalizacao

    var body: some View {
        Section {
            ForEach(Aba.doCabecalho, id: \.self) { aba in
                let ligada = personalizacao.abas.contains(aba)
                HStack {
                    Toggle(isOn: Binding(get: { ligada }, set: { _ in personalizacao.alternar(aba) })) {
                        Label(aba.nome, systemImage: aba.simbolo)
                    }
                    .disabled(aba == .inicio)  // é onde as atividades aparecem: fica sempre
                    Spacer()
                    if ligada { setas(aba, em: personalizacao.abas) { personalizacao.abas = $0 } }
                }
            }
        } header: {
            Text("Abas da ilha")
        } footer: {
            Text("A ilha abre na primeira aba ligada (no Início quando chega um aviso). O Espelho e os Atalhos da Apple ficam na aba Atalhos.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            HStack {
                Slider(value: Binding(get: { personalizacao.opacidade }, set: { personalizacao.opacidade = $0 }),
                       in: Personalizacao.opacidadeMinima...1, step: 0.05) {
                    Text("Fundo da ilha aberta")
                }
                Text(verbatim: personalizacao.opacidade >= 1 ? String(localized: "Preta")
                     : "\(Int((personalizacao.opacidade * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        } header: {
            Text("Fundo")
        } footer: {
            Text("Em 100%, a ilha preta de sempre. Abaixo disso, ela vira vidro escurecido e deixa ver o que está atrás. Fechada, ela continua preta, para se fundir ao notch.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("O que o Início mostra") {
            ForEach(Personalizacao.Secao.allCases, id: \.self) { secao in
                Toggle(nome(secao), isOn: Binding(get: { personalizacao.mostra(secao) },
                                                  set: { _ in personalizacao.alternar(secao) }))
            }
        }

        Section {
            ForEach(personalizacao.asas, id: \.self) { asa in
                HStack {
                    Text(nome(asa))
                    Spacer()
                    setas(asa, em: personalizacao.asas) { personalizacao.asas = $0 }
                }
            }
        } header: {
            Text("Ilha fechada: a vez de cada um")
        } footer: {
            Text("Mostra o primeiro da lista que tem algo agora. Reunião começando e o Claude pedindo permissão passam na frente de tudo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func setas<T: Equatable>(_ item: T, em lista: [T], aplicar: @escaping ([T]) -> Void) -> some View {
        HStack(spacing: 2) {
            Button("Subir", systemImage: "chevron.up") { aplicar(Personalizacao.mover(item, -1, em: lista)) }
                .disabled(lista.first == item)
            Button("Descer", systemImage: "chevron.down") { aplicar(Personalizacao.mover(item, 1, em: lista)) }
                .disabled(lista.last == item)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    private func nome(_ secao: Personalizacao.Secao) -> LocalizedStringKey {
        switch secao {
        case .hoje: "Próximo evento e tempo"
        case .interesse: "Interesses"
        case .claude: "Sessões do Claude"
        case .tocando: "Tocando agora"
        case .apps: "Apps e Mac"
        case .bandeja: "Bandeja de arquivos"
        }
    }

    private func nome(_ asa: Asa) -> LocalizedStringKey {
        switch asa {
        case .reuniao: "Reunião chegando"
        case .timer: "Timer correndo"
        case .atividades: "Avisos"
        case .placar: "Placar ao vivo"
        case .tocando: "Música tocando"
        case .privacidade: "Microfone e câmera"
        case .bandeja: "Bandeja"
        case .nada: "Nada"
        }
    }
}
