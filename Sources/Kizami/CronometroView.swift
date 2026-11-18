import SwiftUI

/// A aba do timer na ilha aberta: parado, os presets numa fileira como a grade de atalhos; rodando, a contagem e os controles.
struct AbaTimer: View {
    let estado: EstadoIlha
    let cronometro: Cronometro

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
            // Os dos Ajustes: no máximo cinco (`Cronometro.maxLivres`), o que cabe na largura da ilha.
            ForEach(cronometro.presets, id: \.self) { preset in
                Button {
                    cronometro.iniciar(minutos: preset.minutos, modo: preset.modo)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: preset.modo.simbolo).font(.system(size: 17, weight: .medium)).frame(height: 22)
                        Text(verbatim: preset.modo.nome).font(.caption2.weight(.semibold))
                        Text(verbatim: "\(preset.minutos) min").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .vidroDeControle(raio: 12)
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
                TextoDaContagem(cronometro: cronometro, fonte: .system(size: 28, weight: .bold, design: .rounded), animado: true)
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
                .glassEffect(.regular, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(ajuda)
    }
}

/// A seção Timer dos Ajustes: os minutos do foco e da pausa do pomodoro e os timers livres da aba.
struct AjustesTimer: View {
    @Bindable var cronometro: Cronometro

    init(cronometro: Cronometro) {
        self.cronometro = cronometro
    }

    var body: some View {
        Section("Timer") {
            Stepper(value: $cronometro.minutosFoco, in: Cronometro.faixaFoco) {
                Text("Foco: \(cronometro.minutosFoco) min")
            }
            Stepper(value: $cronometro.minutosPausa, in: Cronometro.faixaPausa) {
                Text("Pausa: \(cronometro.minutosPausa) min")
            }
            HStack {
                TextField("Timers livres (minutos)", text: $cronometro.textoLivres, prompt: Text(verbatim: "10, 15"))
                    .onSubmit(cronometro.aplicarTextoLivres)
                Button("Aplicar", action: cronometro.aplicarTextoLivres)
                    .disabled(Cronometro.livres(de: cronometro.textoLivres) == cronometro.livres)
            }
            Text("Ao fim do foco, clique no aviso para começar a pausa; ao fim da pausa, para voltar ao foco. Até 3 timers livres, de 1 a 240 minutos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Só a contagem, para a asa da ilha fechada (o ícone do modo fica na outra asa).
struct ContagemNaAsa: View {
    let cronometro: Cronometro

    init(cronometro: Cronometro) {
        self.cronometro = cronometro
    }

    var body: some View {
        TextoDaContagem(cronometro: cronometro, fonte: .caption.weight(.bold), animado: false)
            .opacity(cronometro.pausado ? 0.5 : 1)
    }
}

/// A contagem que se atualiza sozinha a cada segundo.
struct TextoDaContagem: View {
    let cronometro: Cronometro
    let fonte: Font
    /// Na asa, sem animação: o SwiftUI redesenha a ilha inteira na CPU a cada quadro de animação, e o número rolando
    /// todo segundo deixava o Kizami em ~15% de CPU durante o timer inteiro (medido com `top` e `sample`). Na aba
    /// aberta, que fica à vista por pouco tempo, o número rola.
    let animado: Bool

    var body: some View {
        // Os tiques caem 20 ms depois de cada segundo inteiro do fim: com o texto arredondado para cima,
        // um tique com outra fase deixaria o número atrasado até quase um segundo.
        let fase = (cronometro.fim?.timeIntervalSinceReferenceDate ?? 0).truncatingRemainder(dividingBy: 1)
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: fase + 0.02), by: 1)) { contexto in
            let texto = Cronometro.texto(cronometro.restante(agora: contexto.date))
            Text(verbatim: texto)
                .font(fonte).monospacedDigit()
                .contentTransition(animado ? .numericText(countsDown: true) : .identity)
                .animation(animado ? .snappy : nil, value: texto)
        }
    }
}

/// O timer num quadrado. Correndo ou pausado: o modo, a contagem grande e quando termina, e o clique abre a aba.
/// Parado (entra para fechar um par na grade): o foco padrão pronto, e o clique já começa.
struct WidgetTimer: View {
    let cronometro: Cronometro
    let estado: EstadoIlha

    var body: some View {
        if cronometro.ativo {
            Quadro(id: "timer", estado: estado, acao: { estado.aba = .timer }) {
                Cabeca(rotulo: Text(verbatim: cronometro.modo.nome), simbolo: cronometro.modo.simbolo, cor: .orange)
                Valor { TextoDaContagem(cronometro: cronometro, fonte: Tipo.numero, animado: false) }
                Detalhe {
                    if cronometro.pausado {
                        Text("pausado")
                    } else if let fim = cronometro.fim {
                        Text("termina às \(fim.formatted(date: .omitted, time: .shortened))")
                    }
                }
            }
        } else {
            let minutos = cronometro.minutosFoco
            Quadro(id: "timer", estado: estado, acao: { cronometro.iniciar(minutos: minutos, modo: .foco) }) {
                Cabeca(rotulo: Text(verbatim: Cronometro.Modo.foco.nome), simbolo: Cronometro.Modo.foco.simbolo, cor: .orange)
                Valor { Text(verbatim: String(format: "%d:00", minutos)) }
                Detalhe { Text("clique para começar") }
            }
        }
    }
}
