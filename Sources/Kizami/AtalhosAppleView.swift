import SwiftUI

/// Os atalhos da Apple escolhidos, numa fileira embaixo da grade da aba Atalhos, no estilo das skills do Kanji.
struct FileiraAtalhosApple: View {
    let estado: EstadoIlha
    let atalhos: AtalhosApple

    static let altura: CGFloat = 44

    init(estado: EstadoIlha, atalhos: AtalhosApple) {
        self.estado = estado
        self.atalhos = atalhos
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(atalhos.escolhidos, id: \.self) { nome in
                    Button {
                        // A ilha recolhe antes, como na grade: o atalho age no app da pessoa, não em cima da ilha.
                        estado.recolher = true
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            atalhos.rodar(nome)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 12, weight: .medium))
                            Text(verbatim: Atividade.limpo(nome, ate: 30)).font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .frame(minWidth: 72, maxHeight: .infinity, alignment: .leading)
                        .vidroDeControle(raio: 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: Atividade.limpo(nome, ate: 120)))
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: Self.altura)
    }
}

/// A seção dos Ajustes: quais atalhos do app Atalhos viram botões na ilha, e em que ordem.
struct AjustesAtalhosApple: View {
    let atalhos: AtalhosApple

    init(atalhos: AtalhosApple) {
        self.atalhos = atalhos
    }

    /// Os escolhidos primeiro, na ordem dos botões; depois o resto do app Atalhos.
    private var linhas: [String] {
        atalhos.escolhidos + atalhos.disponiveis.filter { !atalhos.escolhidos.contains($0) }
    }

    var body: some View {
        Section("Atalhos da Apple") {
            if atalhos.leituraFalhou {
                Text("Não deu para ler os atalhos deste Mac.").font(.caption).foregroundStyle(.orange)
            } else if linhas.isEmpty {
                Text("Nenhum atalho no app Atalhos.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(linhas, id: \.self) { nome in
                linha(nome)
            }
            Button("Reler os atalhos") { Task { await atalhos.recarregar() } }
            Text("Os atalhos escolhidos viram botões na aba Atalhos da ilha.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await atalhos.recarregar() }
    }

    private func linha(_ nome: String) -> some View {
        let escolhido = atalhos.escolhidos.contains(nome)
        let cheio = !escolhido && atalhos.escolhidos.count >= AtalhosApple.maximo
        return HStack {
            Toggle(isOn: Binding(get: { escolhido }, set: { _ in atalhos.alternar(nome) })) {
                Text(verbatim: Atividade.limpo(nome, ate: 60)).lineLimit(1)
            }
            .disabled(cheio)
            .help(cheio ? Text("No máximo 6 atalhos") : Text(verbatim: ""))
            if escolhido {
                Button { atalhos.subir(nome) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(atalhos.escolhidos.first == nome)
                    .help(Text("Mover para a esquerda na ilha"))
            }
        }
    }
}
