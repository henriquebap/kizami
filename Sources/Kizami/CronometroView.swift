import SwiftUI

/// A aba do timer na ilha aberta: parado, os presets numa fileira como a grade de atalhos; rodando, a contagem e os controles.
struct AbaTimer: View {
    let estado: EstadoIlha
    let cronometro: Cronometro

    /// Cabem cinco na largura da ilha, como os seis atalhos. Minutos únicos: servem de id.
    static let presets: [(minutos: Int, modo: Cronometro.Modo)] = [
        (Cronometro.minutosFoco, .foco), (Cronometro.minutosPausa, .pausa), (10, .livre), (15, .livre), (50, .foco),
    ]

    init(estado: EstadoIlha, cronometro: Cronometro) {
        self.estado = estado
        self.cronometro = cronometro
    }

    var body: some View {
        Group {
            if cronometro.ativo { contagem } else { presets }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: Geometria.alturaAtalhos)
    }

    private var presets: some View {
        HStack(spacing: 4) {
            ForEach(Self.presets, id: \.minutos) { preset in
                Button {
                    cronometro.iniciar(minutos: preset.minutos, modo: preset.modo)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: preset.modo.simbolo).font(.system(size: 17, weight: .medium)).frame(height: 22)
                        Text(verbatim: preset.modo.nome).font(.caption2.weight(.semibold))
                        Text(verbatim: "\(preset.minutos) min").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var contagem: some View {
        HStack(spacing: 12) {
            Image(systemName: cronometro.modo.simbolo).font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: cronometro.pausado ? String(localized: "Pausado") : cronometro.modo.nome)
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                TextoDaContagem(cronometro: cronometro, fonte: .system(size: 28, weight: .bold, design: .rounded))
                    .opacity(cronometro.pausado ? 0.5 : 1)
            }
            Spacer(minLength: 0)
            if cronometro.pausado {
                controle("play.fill", Text("Continuar")) { cronometro.continuar() }
            } else {
                controle("pause.fill", Text("Pausar")) { cronometro.pausar() }
            }
            controle("stop.fill", Text("Parar")) { cronometro.parar() }
        }
    }

    private func controle(_ simbolo: String, _ ajuda: Text, acao: @escaping @MainActor () -> Void) -> some View {
        Button(action: acao) {
            Image(systemName: simbolo).font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.1)))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(ajuda)
    }
}

/// Só a contagem, para a asa da ilha fechada (o ícone do modo fica na outra asa).
struct ContagemNaAsa: View {
    let cronometro: Cronometro

    init(cronometro: Cronometro) {
        self.cronometro = cronometro
    }

    var body: some View {
        TextoDaContagem(cronometro: cronometro, fonte: .caption.weight(.bold))
            .opacity(cronometro.pausado ? 0.5 : 1)
    }
}

/// A contagem que se atualiza sozinha a cada segundo.
private struct TextoDaContagem: View {
    let cronometro: Cronometro
    let fonte: Font

    var body: some View {
        // Os tiques caem 20 ms depois de cada segundo inteiro do fim: com o texto arredondado para cima,
        // um tique com outra fase deixaria o número atrasado até quase um segundo.
        let fase = (cronometro.fim?.timeIntervalSinceReferenceDate ?? 0).truncatingRemainder(dividingBy: 1)
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: fase + 0.02), by: 1)) { contexto in
            let texto = Cronometro.texto(cronometro.restante(agora: contexto.date))
            Text(verbatim: texto)
                .font(fonte).monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: texto)
        }
    }
}
