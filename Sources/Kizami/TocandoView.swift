import SwiftUI

extension TocandoAgora {
    /// A cor da capa, já ajustada para o preto (`Capa.destaque`). Sem capa ou com capa cinza, nada.
    var corDeDestaque: Color? { cor?.cor }

    /// O artista e o app, ou "Tocando agora" quando o player não conta a faixa.
    var subtitulo: String {
        metadados?.titulo == nil ? String(localized: "Tocando agora")
            : [metadados?.artista, nomeDoApp].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A música em destaque: a capa (que voou da asa), o app, o título, o artista e os botões, no fundo tingido pela capa.
/// Clique: expande no lugar, com o tempo e a barra. A barra não fica aqui: ler a posição do player custa um
/// AppleScript por segundo, e só vale a pena com a música expandida.
struct CartaoMusica: View {
    let tocando: TocandoAgora
    let estado: EstadoIlha
    let espaco: Namespace.ID
    let aoClicar: () -> Void

    var body: some View {
        let cor = tocando.corDeDestaque
        HStack(spacing: 14) {
            Miniatura(tocando: tocando, lado: 56, raio: 14)
                .matchedGeometryEffect(id: "capa", in: espaco)
            VStack(alignment: .leading, spacing: 2) {
                // verbatim: título, artista e o nome do app vêm do player e não podem virar Markdown nem chave de tradução.
                Text(verbatim: tocando.nomeDoApp).estiloRotulo(cor)
                Text(verbatim: tocando.metadados?.titulo ?? tocando.nomeDoApp).font(Tipo.titulo)
                Text(verbatim: tocando.subtitulo).font(Tipo.corpo).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .contentTransition(.opacity)
            Spacer(minLength: 4)
            ControlesDoPlayer(tocando: tocando, grande: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cartao(cor: cor, raio: Geometria.raioDoWidget, realce: estado.cartaoSobCursor == "musica", id: "musica", em: espaco)
        .contentShape(.rect)
        .realce("musica", estado)
        .onTapGesture(perform: aoClicar)
        .accessibilityAddTraits(.isButton)
    }
}

/// A música num quadrado, quando outra coisa tem o destaque (a reunião, o Claude).
struct WidgetMusica: View {
    let tocando: TocandoAgora
    let estado: EstadoIlha
    let espaco: Namespace.ID
    let aoClicar: () -> Void

    var body: some View {
        Quadro(id: "musica", estado: estado, cor: tocando.corDeDestaque, acao: aoClicar, espaco: espaco) {
            HStack(spacing: 6) {
                Miniatura(tocando: tocando, lado: 36, raio: 8).matchedGeometryEffect(id: "capa", in: espaco)
                Spacer(minLength: 0)
                ControlesDoPlayer(tocando: tocando)
            }
            Spacer(minLength: 0)
            Group {
                Text(verbatim: tocando.metadados?.titulo ?? tocando.nomeDoApp).font(.system(size: 13, weight: .semibold))
                Text(verbatim: tocando.subtitulo).font(Tipo.corpo).foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }
}

/// Os botões do player: anterior, tocar ou pausar e próxima no Music e no Spotify; num navegador, sem AppleScript
/// para o player, a tecla de play/pause do teclado, que o macOS entrega a quem está tocando (o YouTube no Chrome
/// ou no Safari).
struct ControlesDoPlayer: View {
    let tocando: TocandoAgora
    /// No cartão de destaque, o play ganha um círculo: é o botão que mais se usa.
    var grande = false

    var body: some View {
        if let app = tocando.app, Controle.sabeControlar(app) {
            Controles(app: app, pausado: tocando.pausado, grande: grande)
        } else {
            HStack(spacing: 6) {
                Barras(altura: 16, cor: tocando.corDeDestaque)
                Button("Tocar ou pausar", systemImage: "playpause.fill") { TeclaDeMidia.tocarOuPausar() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(EstiloBotao())
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
                    .help(Text("Tocar ou pausar"))
            }
        }
    }
}

/// Anterior, tocar ou pausar, próxima. A ilha aberta aceita clique sem ativar o Kizami (painel que não vira key):
/// o foco continua no app em que a pessoa está.
private struct Controles: View {
    let app: String
    let pausado: Bool
    let grande: Bool

    var body: some View {
        HStack(spacing: 2) {
            botao("Anterior", "backward.fill", .anterior, tamanho: 13)
            botao(pausado ? "Tocar" : "Pausar", pausado ? "play.fill" : "pause.fill", .alternar, tamanho: 18)
                .contentTransition(.symbolEffect(.replace))
                .background { if grande { Circle().fill(.white.opacity(0.14)).frame(width: 38, height: 38) } }
            botao("Próxima", "forward.fill", .proxima, tamanho: 13)
        }
    }

    private func botao(_ nome: LocalizedStringKey, _ simbolo: String, _ acao: Controle.Acao, tamanho: CGFloat) -> some View {
        Button(nome, systemImage: simbolo) { Controle.enviar(acao, app: app) }
            .labelStyle(.iconOnly)
            .buttonStyle(EstiloBotao())
            .font(.system(size: tamanho, weight: .semibold))
            .frame(width: 30, height: 30)
            .contentShape(.rect)
            .help(Text(nome))
    }
}

/// A capa, quando o player dá; senão o ícone do app que está tocando.
struct Miniatura: View {
    let tocando: TocandoAgora
    let lado: CGFloat
    let raio: CGFloat

    var body: some View {
        Group {
            if let capa = tocando.capa {
                Image(nsImage: capa).resizable().aspectRatio(contentMode: .fill)
                    .transition(.blurReplace)
            } else if let icone = tocando.icone {
                Image(nsImage: icone).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "music.note").foregroundStyle(.secondary)
            }
        }
        .frame(width: lado, height: lado)
        .clipShape(.rect(cornerRadius: raio))
        .animation(Movimento.ou(Movimento.conteudo), value: tocando.capa)
    }
}

/// Equalizador de enfeite: as barras não leem o som (isso pediria gravar a saída), só mostram que há som.
/// Animado pelo Core Animation, que roda no servidor de janelas: com um `TimelineView` a 15 quadros por segundo, o
/// SwiftUI redesenhava a ilha inteira na CPU a cada quadro (capa, texto, sombra), e o Kizami ficava em ~33% de CPU
/// enquanto qualquer coisa tocava (medido com `top` e `sample`).
struct Barras: View {
    let altura: CGFloat
    /// A cor da capa: a asa lê como uma coisa só com a capa do outro lado (HIG, Live Activities).
    var cor: Color?

    var body: some View {
        CamadaDeBarras(altura: altura, cor: cor.map(NSColor.init) ?? .white).frame(width: 4 * 3 + 3 * 2, height: altura)
    }
}

private struct CamadaDeBarras: NSViewRepresentable {
    let altura: CGFloat
    let cor: NSColor

    func makeNSView(context: Context) -> NSView {
        let vista = NSView()
        vista.wantsLayer = true
        let parado = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for i in 0..<4 {
            let barra = CALayer()
            barra.backgroundColor = cor.withAlphaComponent(0.85).cgColor
            barra.cornerRadius = 1.5
            barra.transform = CATransform3DMakeScale(1, 0.6, 1)
            if !parado {
                // Durações e fases diferentes: as quatro nunca sobem juntas, como o seno de antes.
                let pulso = CABasicAnimation(keyPath: "transform.scale.y")
                pulso.fromValue = 0.3
                pulso.toValue = 1
                pulso.duration = 0.38 + Double(i) * 0.11
                pulso.timeOffset = Double(i) * 0.21
                pulso.autoreverses = true
                pulso.repeatCount = .infinity
                pulso.isRemovedOnCompletion = false  // a janela some em tela cheia e volta: a animação continua
                pulso.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                barra.add(pulso, forKey: "pulso")
            }
            vista.layer?.addSublayer(barra)
        }
        posicionar(vista)
        return vista
    }

    func updateNSView(_ vista: NSView, context: Context) {
        posicionar(vista)
        // Só a cor da layer, sem a transição implícita: a animação das barras continua sem recomeçar.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        vista.layer?.sublayers?.forEach { $0.backgroundColor = cor.withAlphaComponent(0.85).cgColor }
        CATransaction.commit()
    }

    /// `bounds` e `position` em vez de `frame`, que não vale numa layer com `transform`. Escala a partir do meio.
    private func posicionar(_ vista: NSView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, barra) in (vista.layer?.sublayers ?? []).enumerated() {
            barra.bounds = CGRect(x: 0, y: 0, width: 3, height: altura)
            barra.position = CGPoint(x: CGFloat(i) * 5 + 1.5, y: altura / 2)
        }
        CATransaction.commit()
    }
}

/// A música que cresceu da linha: a capa grande, o título, os botões e, no Music e no Spotify, o tempo com a barra
/// que se arrasta para pular.
struct MusicaExpandida: View {
    let estado: EstadoIlha
    let tocando: TocandoAgora
    let espaco: Namespace.ID
    let aoRecolher: () -> Void

    var body: some View {
        let app = tocando.app
        let barra = app.map(Controle.sabeControlar) == true
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Miniatura(tocando: tocando, lado: Geometria.capaGrande, raio: 14)
                    .matchedGeometryEffect(id: "capa", in: espaco)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 4) {
                        // verbatim: título e artista vêm do player.
                        Text(verbatim: tocando.metadados?.titulo ?? tocando.nomeDoApp)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Recolher", systemImage: "chevron.up", action: aoRecolher)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(.rect)
                            .help(Text("Recolher"))
                    }
                    Text(verbatim: [tocando.metadados?.artista, tocando.nomeDoApp].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    ControlesDoPlayer(tocando: tocando)
                }
                .lineLimit(1)
                .contentTransition(.opacity)
            }
            .frame(height: Geometria.capaGrande)
            .contentShape(.rect)
            .onTapGesture(perform: aoRecolher)  // os botões dentro continuam só botões
            if let app, barra {
                BarraDoTempo(estado: estado, app: app).frame(height: 22)
            }
        }
        .padding(12)
        .frame(height: Geometria.alturaMusica(barra: barra), alignment: .top)
        .cartao(cor: tocando.corDeDestaque, raio: Geometria.raioDoWidget, id: "musica", em: espaco)
        .padding(.horizontal, 4)
    }
}

/// O tempo da faixa e a barra. A `Janela` lê o player a cada segundo; entre uma leitura e outra o relógio daqui anda
/// sozinho, uma vez por segundo, e só enquanto toca: pausado, nada redesenha.
private struct BarraDoTempo: View {
    let estado: EstadoIlha
    let app: String

    var body: some View {
        // Uma view só, com o relógio pausado em vez de trocado: com um `if`, o primeiro toque na barra (que liga o
        // `arrastandoEm`) trocava a view no meio do gesto, o gesto era cancelado e a barra ficava presa sem pular.
        let progresso = estado.progresso
        let parado = !(progresso?.tocando ?? false) || estado.arrastandoEm != nil
        TimelineView(.animation(minimumInterval: 1, paused: parado)) { contexto in
            conteudo(progresso, agora: parado ? (progresso?.lidoEm ?? .now) : contexto.date)
        }
    }

    /// Sem a primeira leitura (ou com a Automação negada), a barra vazia e o tempo em branco.
    private func conteudo(_ progresso: Progresso?, agora: Date) -> some View {
        let duracao = progresso?.duracao ?? 0
        let fracao = estado.arrastandoEm ?? (duracao > 0 ? (progresso?.posicao(em: agora) ?? 0) / duracao : 0)
        let atual = fracao * duracao
        return HStack(spacing: 8) {
            Text(verbatim: progresso == nil ? "–:––" : Progresso.tempo(atual))
                .frame(width: 44, alignment: .trailing)
            GeometryReader { caixa in
                let largura = max(caixa.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white).frame(width: largura * fracao)
                }
                .frame(height: estado.arrastandoEm == nil ? 4 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { toque in
                        guard duracao > 0 else { return }
                        estado.arrastandoEm = min(max(toque.location.x / largura, 0), 1)
                    }
                    .onEnded { toque in
                        guard let progresso, duracao > 0 else { return }
                        let alvo = min(max(toque.location.x / largura, 0), 1) * duracao
                        Controle.irPara(alvo, duracao: duracao, app: app)
                        // Mostra já onde soltou; a próxima leitura confirma.
                        estado.progresso = Progresso(posicao: alvo, duracao: duracao, tocando: progresso.tocando, lidoEm: .now)
                        estado.arrastandoEm = nil
                    })
            }
            Text(verbatim: progresso == nil ? "–:––" : "-" + Progresso.tempo(duracao - atual))
                .frame(width: 48, alignment: .leading)
        }
        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
    }
}
