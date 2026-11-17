import SwiftUI

/// O Início em grade (v0.16): o cartão de destaque em cima, os avisos, os widgets aos pares e a bandeja.
/// O que vai em cada fileira é a regra pura `Painel`; aqui só se desenha.
struct InicioEmGrade: View {
    let estado: EstadoIlha
    let fontes: Fontes
    let painel: Painel
    /// O mesmo da ilha: a capa e o ponto da reunião voam da asa fechada para cá ao abrir.
    let espaco: Namespace.ID
    let alternar: (EstadoIlha.Expansao) -> Void

    var body: some View {
        VStack(spacing: Painel.espaco) {
            ForEach(Array(painel.fileiras.enumerated()), id: \.element) { ordem, fileira in
                Group {
                    switch fileira {
                    case .larga(let largo): self.largo(largo)
                    case .dupla(let a, let b):
                        HStack(spacing: Painel.espaco) { widget(a); widget(b) }
                    case .sozinha(let w): widget(w)
                    }
                }
                .frame(height: altura(fileira))
                .entrada(ordem)
            }
        }
        .padding(.horizontal, 4)
    }

    private func altura(_ fileira: Painel.Fileira) -> CGFloat {
        if case .larga(let largo) = fileira { Painel.altura(largo) } else { Painel.alturaWidget }
    }

    @ViewBuilder private func largo(_ largo: Painel.Largo) -> some View {
        switch largo {
        case .claude: CartaoClaude(sessoes: fontes.claude)
        case .reuniao: CartaoReuniao(agenda: fontes.agenda, espaco: espaco)
        case .musica: CartaoMusica(tocando: fontes.tocando, estado: estado, espaco: espaco) { alternar(.musica) }
        case .dia: CartaoDia(agenda: fontes.agenda, tempo: fontes.tempo, estado: estado) { alternar(.agenda) }
        case .atividades: Lista(mural: fontes.mural, estado: estado, ocultos: avisosNoDestaque(fontes)).padding(.horizontal, -4)
        case .bandeja: FileiraDaBandeja(bandeja: fontes.bandeja, alvo: estado.alvo).padding(.horizontal, -6)
        }
    }

    @ViewBuilder private func widget(_ w: Painel.Widget) -> some View {
        switch w {
        case .tempo: WidgetTempo(tempo: fontes.tempo, estado: estado)
        case .agenda: WidgetAgenda(agenda: fontes.agenda, estado: estado) { alternar(.agenda) }
        case .sessoes: WidgetSessoes(sessoes: fontes.claude, estado: estado)
        case .musica: WidgetMusica(tocando: fontes.tocando, estado: estado, espaco: espaco) { alternar(.musica) }
        case .timer: WidgetTimer(cronometro: fontes.cronometro, estado: estado)
        case .lembretes: WidgetLembretes(lembretes: fontes.lembretes, estado: estado)
        case .interesse: WidgetInteresse(interesses: fontes.interesses, estado: estado)
        case .mac: WidgetMac(mac: fontes.mac, estado: estado)
        }
    }
}

/// O aviso "Claude precisa de você" da sessão que já está no cartão de destaque: na lista seria a mesma coisa duas vezes.
@MainActor func avisosNoDestaque(_ f: Fontes) -> Set<String> {
    Set(f.claude.sessoes.filter { $0.estado == .precisaDeVoce }.map { "claude-\($0.id)" })
}

/// Um quadrado da grade: 12 pt de folga, o conteúdo de cima para baixo, o realce sob o cursor quando faz algo.
struct Quadro<Conteudo: View>: View {
    let id: String
    let estado: EstadoIlha
    let cor: Color?
    let acao: (() -> Void)?
    let conteudo: Conteudo

    init(id: String, estado: EstadoIlha, cor: Color? = nil, acao: (() -> Void)? = nil, @ViewBuilder conteudo: () -> Conteudo) {
        self.id = id
        self.estado = estado
        self.cor = cor
        self.acao = acao
        self.conteudo = conteudo()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) { conteudo }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cartao(cor: cor, raio: Geometria.raioDoWidget, realce: acao != nil && estado.cartaoSobCursor == id)
            .contentShape(.rect(cornerRadius: Geometria.raioDoWidget))
            .realce(id, estado)
            .onTapGesture { acao?() }
            .accessibilityAddTraits(acao == nil ? [] : .isButton)
    }
}

/// A linha de cima de um quadrado: o rótulo à esquerda e um símbolo (ou um ponto na cor do calendário) à direita.
struct Cabeca: View {
    let rotulo: Text
    var simbolo: String?
    var cor: Color = .secondary
    var ponto: Color?

    var body: some View {
        HStack(spacing: 4) {
            rotulo.estiloRotulo()
            Spacer(minLength: 4)
            if let ponto { Circle().fill(ponto).frame(width: 8, height: 8) }
            if let simbolo {
                Image(systemName: simbolo).font(.system(size: 13, weight: .semibold)).foregroundStyle(cor)
            }
        }
    }
}

/// O botão verde de entrar numa reunião, em qualquer lugar da ilha.
struct BotaoEntrar: View {
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Text("Entrar")
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(.green))
                .foregroundStyle(.black.opacity(0.85))
        }
        .buttonStyle(EstiloBotao())
        .fixedSize()
    }
}

extension SIMD3<Double> {
    var cor: Color { Color(red: x, green: y, blue: z) }
}
