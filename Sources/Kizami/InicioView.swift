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
        // A margem dos lados (`Painel.margem`): 10 pt da ilha (a orelha) e o resto daqui.
        .padding(.horizontal, Painel.margem - 10)
    }

    private func altura(_ fileira: Painel.Fileira) -> CGFloat {
        if case .larga(let largo) = fileira { Painel.altura(largo) } else { Painel.alturaWidget }
    }

    @ViewBuilder private func largo(_ largo: Painel.Largo) -> some View {
        switch largo {
        case .claude: CartaoClaude(sessoes: fontes.claude)
        case .reuniao: CartaoReuniao(agenda: fontes.agenda, espaco: espaco)
        case .musica: CartaoMusica(tocando: fontes.tocando, estado: estado, espaco: espaco) { alternar(.musica) }
        case .dia: CartaoDia(agenda: fontes.agenda, tempo: fontes.tempo, estado: estado, espaco: espaco) { alternar(.agenda) }
        case .atividades: Lista(mural: fontes.mural, estado: estado, ocultos: avisosNoDestaque(fontes))
        case .bandeja: FileiraDaBandeja(bandeja: fontes.bandeja, alvo: estado.alvo).padding(.horizontal, -10)
        }
    }

    @ViewBuilder private func widget(_ w: Painel.Widget) -> some View {
        switch w {
        case .tempo: WidgetTempo(tempo: fontes.tempo, estado: estado)
        case .agenda: WidgetAgenda(agenda: fontes.agenda, estado: estado, espaco: espaco) { alternar(.agenda) }
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
/// Com a seção do Claude escondida não há cartão, e o aviso fica na lista.
@MainActor func avisosNoDestaque(_ f: Fontes) -> Set<String> {
    guard f.personalizacao.mostra(.claude) else { return [] }
    return Set(f.claude.sessoes.filter { $0.estado == .precisaDeVoce }.map { "claude-\($0.id)" })
}

/// Um quadrado da grade. Monte com `Cabeca`, `Valor`, `Detalhe` e `Rodape`: cada um tem altura fixa (`Painel`), então
/// o rótulo, o número e o detalhe de um widget ficam na mesma linha que os do vizinho.
struct Quadro<Conteudo: View>: View {
    let id: String
    let estado: EstadoIlha
    let cor: Color?
    let acao: (() -> Void)?
    /// Com o espaço, o fundo cresce até o item expandido de mesmo id (a agenda, a música).
    let espaco: Namespace.ID?
    let conteudo: Conteudo

    init(id: String, estado: EstadoIlha, cor: Color? = nil, acao: (() -> Void)? = nil, espaco: Namespace.ID? = nil,
         @ViewBuilder conteudo: () -> Conteudo) {
        self.id = id
        self.estado = estado
        self.cor = cor
        self.acao = acao
        self.espaco = espaco
        self.conteudo = conteudo()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { conteudo }
            .padding(Painel.folga)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cartao(cor: cor, raio: Painel.raio, realce: acao != nil && estado.cartaoSobCursor == id,
                    id: espaco == nil ? nil : id, em: espaco)
            .contentShape(.rect(cornerRadius: Painel.raio))
            .realce(id, estado)
            .onTapGesture { acao?() }
            .accessibilityAddTraits(acao == nil ? [] : .isButton)
    }
}

/// O trilho de cima: o rótulo à esquerda e um símbolo (ou um ponto na cor do calendário) à direita.
struct Cabeca: View {
    let rotulo: Text
    var simbolo: String?
    var cor: Color = .secondary
    var ponto: Color?

    var body: some View {
        HStack(spacing: 4) {
            rotulo.estiloRotulo()
            Spacer(minLength: 4)
            if let ponto { Circle().fill(ponto).frame(width: 7, height: 7) }
            if let simbolo {
                Image(systemName: simbolo).font(.system(size: 11, weight: .semibold)).foregroundStyle(cor)
            }
        }
        .frame(height: Painel.alturaRotulo)
    }
}

/// O trilho do número: 24 pt arredondado, e o que mais couber na linha (um símbolo, um botão) à direita.
struct Valor<Conteudo: View>: View {
    let conteudo: Conteudo
    init(@ViewBuilder _ conteudo: () -> Conteudo) { self.conteudo = conteudo() }

    var body: some View {
        HStack(alignment: .center, spacing: 6) { conteudo }
            .font(Tipo.numero).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Painel.alturaValor)
            .padding(.top, 4)
    }
}

/// O trilho de baixo do número: uma linha de texto secundário.
struct Detalhe<Conteudo: View>: View {
    let conteudo: Conteudo
    init(@ViewBuilder _ conteudo: () -> Conteudo) { self.conteudo = conteudo() }

    var body: some View {
        HStack(spacing: 4) { conteudo }
            .font(Tipo.corpo).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Painel.alturaDetalhe)
    }
}

/// O trilho do pé do quadro, em legenda. Ponha um `Spacer(minLength: 0)` antes: encostado embaixo, fica na mesma
/// altura em todos.
struct Rodape<Conteudo: View>: View {
    let conteudo: Conteudo
    init(@ViewBuilder _ conteudo: () -> Conteudo) { self.conteudo = conteudo() }

    var body: some View {
        HStack(spacing: 4) { conteudo }
            .font(Tipo.legenda).monospacedDigit().lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Painel.alturaRodape)
    }
}

/// A linha principal dos cartões largos (música, reunião, Claude): o ícone de 40, o rótulo, o título e o detalhe,
/// e o que fica à direita. Um molde só, para os três terem as mesmas medidas.
struct LinhaDeDestaque<Lider: View, Fim: View>: View {
    let rotulo: Text
    let corDoRotulo: Color?
    let titulo: Text
    let detalhe: Text
    let lider: Lider
    let fim: Fim

    init(rotulo: Text, corDoRotulo: Color? = nil, titulo: Text, detalhe: Text,
         @ViewBuilder lider: () -> Lider, @ViewBuilder fim: () -> Fim) {
        self.rotulo = rotulo
        self.corDoRotulo = corDoRotulo
        self.titulo = titulo
        self.detalhe = detalhe
        self.lider = lider()
        self.fim = fim()
    }

    var body: some View {
        HStack(spacing: Painel.folga) {
            lider.frame(width: Painel.icone, height: Painel.icone)
            VStack(alignment: .leading, spacing: 2) {
                rotulo.estiloRotulo(corDoRotulo)
                titulo.font(Tipo.titulo)
                detalhe.font(Tipo.corpo).foregroundStyle(.secondary).monospacedDigit()
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            fim
        }
        .frame(height: Painel.linhaDeDestaque)
    }
}

/// O círculo tingido atrás do símbolo dos cartões largos (a reunião, o Claude).
struct IconeDeDestaque: View {
    let simbolo: String
    let cor: Color

    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(cor)
            .frame(width: Painel.icone, height: Painel.icone)
            .background(Circle().fill(cor.opacity(0.22)))
    }
}

/// O botão em pílula: o mesmo desenho em toda a ilha. `cheio` ocupa a largura (Entrar na reunião).
struct Pilula: View {
    let titulo: LocalizedStringKey
    var simbolo: String?
    let cor: Color
    var altura: CGFloat = Painel.botao
    var cheio = false
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Group {
                if let simbolo { Label(titulo, systemImage: simbolo) } else { Text(titulo) }
            }
            .font(.system(size: altura < Painel.botao ? 11 : 12, weight: .semibold))
            .padding(.horizontal, altura < Painel.botao ? 9 : 12)
            .frame(maxWidth: cheio ? .infinity : nil)
            .frame(height: altura)
            .background(Capsule().fill(cor))
            .foregroundStyle(.black.opacity(0.85))
            .contentShape(.capsule)
        }
        .buttonStyle(EstiloBotao())
        .fixedSize(horizontal: !cheio, vertical: false)
    }
}

/// O botão verde de entrar numa reunião, pequeno, dentro de um widget ou de uma linha.
struct BotaoEntrar: View {
    let acao: () -> Void

    var body: some View {
        Pilula(titulo: "Entrar", cor: .green, altura: 20, acao: acao)
    }
}

extension SIMD3<Double> {
    var cor: Color { Color(red: x, green: y, blue: z) }
}
