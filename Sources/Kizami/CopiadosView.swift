import SwiftUI

/// A aba "Copiados": os últimos textos e imagens copiados, um por linha. Clicar cola no app em que a pessoa está.
struct AbaCopiados: View {
    let estado: EstadoIlha
    let copiados: Copiados

    var body: some View {
        let itens = copiados.itens
        let maximo = Geometria.maximoDoDia
        let visiveis = itens.count > maximo ? maximo - 1 : maximo
        VStack(alignment: .leading, spacing: Geometria.espacoLinha) {
            if !copiados.ligado {
                Button { Kizami.shared.abrirAjustes() } label: {
                    Label("Ligue nos Ajustes", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(height: Geometria.alturaLinha)
            } else if itens.isEmpty {
                Label("Nada copiado ainda", systemImage: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
                    .frame(height: Geometria.alturaLinha)
            }
            ForEach(itens.prefix(visiveis)) { item in
                linha(item)
            }
            if itens.count > visiveis {
                Text(String(localized: "mais \(itens.count - visiveis)"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: Geometria.alturaLinha)
                    .padding(.leading, 28)  // alinhado com o texto, depois do ícone
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Geometria.alturaDaLista(itens: itens.count), alignment: .top)
    }

    private func linha(_ item: ItemCopiado) -> some View {
        // Prefixo no id: `linhaSobCursor` é dividido com a lista do Início, cujos ids vêm de fora.
        let chave = "copiado-\(item.id.uuidString)"
        return HStack(spacing: 10) {
            switch item.conteudo {
            case .texto:
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                // verbatim: o texto veio de qualquer app e não pode virar Markdown nem chave de tradução.
                Text(verbatim: item.resumo).lineLimit(1)
            case .imagem(let imagem):
                miniatura(imagem)
                Text("Imagem · \(imagem.largura)×\(imagem.altura)").lineLimit(1)
            }
            Spacer(minLength: 8)
            if estado.linhaSobCursor == chave {
                Button("Tirar da ilha", systemImage: "xmark.circle.fill") { copiados.remover(item) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .help(Text("Tirar da ilha"))
            } else {
                Text(item.data, style: .relative).font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
        .onHover { dentro in
            if dentro { estado.linhaSobCursor = chave }
            else if estado.linhaSobCursor == chave { estado.linhaSobCursor = nil }
        }
        .frame(height: Geometria.alturaLinha)
        .contentShape(.rect)
        .help(Text("Colar no app em que você está"))
        .onTapGesture {
            // A ilha recolhe antes, como na aba de atalhos: o ⌘V precisa cair no app de baixo, com a ilha fora do caminho.
            estado.recolher = true
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                copiados.colar(item)
            }
        }
        .transition(.blurReplace)
    }

    /// 22 pt cabem na linha de 30 sem aumentá-la (`Geometria.alturaDaLista` continua valendo).
    @ViewBuilder private func miniatura(_ imagem: ItemCopiado.Imagem) -> some View {
        if let miniatura = imagem.miniatura {
            Image(decorative: miniatura, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(.rect(cornerRadius: 4))
        } else {
            Image(systemName: "photo")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }
}

/// A seção dos Ajustes que liga o histórico. Desligado por padrão: guardar o que a pessoa copia é escolha dela.
struct AjustesCopiados: View {
    let copiados: Copiados

    var body: some View {
        Section("Copiados") {
            Toggle("Guardar o que você copia", isOn: Binding(get: { copiados.ligado }, set: { copiados.ligado = $0 }))
            Text("Os últimos 10 textos e imagens ficam só na memória e somem ao fechar o Kizami. Senhas e chaves ficam de fora. Colar pede Acessibilidade.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
