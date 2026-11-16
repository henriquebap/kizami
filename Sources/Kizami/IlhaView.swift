import SwiftUI

/// Os estados da forma, do menor para o maior.
private enum Forma: Equatable {
    case repouso, compacta, aviso, aberta

    var orelha: CGFloat { self == .aberta ? 10 : Geometria.orelha }
    var raio: CGFloat {
        switch self {
        case .repouso: 12
        case .compacta: 14
        case .aviso: 20
        case .aberta: 30
        }
    }
}

/// Tudo o que a ilha mostra: as mesmas instâncias em todos os monitores.
@MainActor struct Fontes {
    let mural: Mural
    let bandeja: Bandeja
    let tocando: TocandoAgora
    let agenda: Agenda
    let tempo: Tempo
    let claude: SessoesClaude
    let mac: Mac
    let interesses: Interesses
}

/// As seções da ilha aberta agora. A janela mede a área do hover com a mesma conta.
@MainActor func secoesAtuais(_ f: Fontes) -> Secoes {
    Secoes(tocando: f.tocando.app != nil, atividades: f.mural.atividades.count,
           arquivos: f.bandeja.arquivos.count, arrastando: f.bandeja.arrastando,
           sessoes: f.claude.sessoes.count, hoje: f.agenda.proximo != nil || f.tempo.previsao != nil,
           apps: !f.mac.emblemas.isEmpty || !f.mac.microfone.isEmpty || f.mac.camera || f.mac.bateria != nil,
           interesse: !f.interesses.proximos.isEmpty)
}

/// A forma preta presa ao topo. Sempre à vista: sem nada, fica em repouso, só um pouco maior que o notch.
struct IlhaView: View {
    let estado: EstadoIlha
    let fontes: Fontes
    private var mural: Mural { fontes.mural }
    private var bandeja: Bandeja { fontes.bandeja }
    private var tocando: TocandoAgora { fontes.tocando }
    /// Microfone ou câmera ligados: como no iPhone, a ilha não fica em repouso escondendo isso.
    private var privacidade: Bool { !fontes.mac.microfone.isEmpty || fontes.mac.camera }

    var body: some View {
        let g = estado.geometria
        let secoes = secoesAtuais(fontes)
        let forma: Forma = estado.aberta ? .aberta
            : !mural.avisos.isEmpty ? .aviso
            : !mural.atividades.isEmpty || !bandeja.arquivos.isEmpty || tocando.app != nil || privacidade ? .compacta
            : .repouso
        let tamanho = switch forma {
        case .repouso: g.repouso
        case .compacta: g.compacta(icones: mural.atividades.isEmpty ? 1 : mural.destaques.count)
        case .aviso: g.aviso(linhas: mural.avisos.count)
        case .aberta: estado.aba == .atalhos ? g.abertaAtalhos : g.aberta(secoes)
        }
        let contorno = FormaIlha(orelha: forma.orelha, raio: forma.raio)

        ZStack(alignment: .top) {
            contorno.fill(.black)
            Group {
                switch forma {
                case .repouso:
                    EmptyView()
                case .compacta:
                    // Atividade tem a vez (foi pedida por alguém); depois o som; por fim a bandeja.
                    let lado = ladoDaAsa(g.notch.height)
                    if let primeira = mural.destaques.first {
                        // Até três ícones, o mais importante encostado no canto: lado a lado, sem empilhar.
                        Asas(altura: g.notch.height) {
                            HStack(spacing: Geometria.iconeExtra - lado) {
                                ForEach(mural.destaques) { atividade in
                                    Simbolo(nome: atividade.simbolo ?? "bell.fill", cor: cor(atividade), chegada: atividade.chegada)
                                        .frame(width: lado, height: lado)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        } direita: {
                            HStack(spacing: 4) {
                                IndicadorPrivacidade(mac: fontes.mac)
                                Contador(total: mural.atividades.count, cor: cor(primeira))
                            }
                        }
                    } else if tocando.app != nil {
                        Asas(altura: g.notch.height) {
                            Miniatura(tocando: tocando, lado: lado, raio: lado / 4)
                                .opacity(tocando.pausado ? 0.55 : 1)
                        } direita: {
                            IndicadorPrivacidade(mac: fontes.mac)
                            if tocando.pausado {
                                Image(systemName: "pause.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                            } else {
                                Barras(altura: lado * 0.6)
                            }
                        }
                    } else if bandeja.arquivos.isEmpty {
                        // Só o microfone ou a câmera: o app que está ouvindo à esquerda, os pontinhos à direita.
                        Asas(altura: g.notch.height) {
                            if let app = fontes.mac.microfone.first {
                                LinhaApps.icone(app).frame(width: lado, height: lado)
                            } else {
                                Simbolo(nome: "video.fill", cor: .green, chegada: nil)
                            }
                        } direita: {
                            IndicadorPrivacidade(mac: fontes.mac)
                        }
                    } else {
                        Asas(altura: g.notch.height) {
                            Simbolo(nome: "tray.full.fill", cor: .white, chegada: nil)
                        } direita: {
                            HStack(spacing: 4) {
                                IndicadorPrivacidade(mac: fontes.mac)
                                Contador(total: bandeja.arquivos.count, cor: .white)
                            }
                        }
                    }
                case .aviso:
                    VStack(spacing: Geometria.espacoLinha) {
                        ForEach(mural.avisos) { aviso in
                            LinhaDeAviso(atividade: aviso)
                                .frame(height: Geometria.alturaLinha)
                                .transition(.blurReplace)
                        }
                    }
                    .padding(.top, g.faixaDoTopo)  // a faixa do notch é a câmera: o texto vem abaixo
                case .aberta:
                    VStack(spacing: Geometria.espacoSecao) {
                        Cabecalho(estado: estado, mural: mural)
                        if estado.aba == .atalhos {
                            GradeDeAtalhos(estado: estado, mural: mural)
                        } else {
                        if secoes.hoje { LinhaHoje(agenda: fontes.agenda, tempo: fontes.tempo) }
                        if secoes.interesse { LinhaInteresse(interesses: fontes.interesses) }
                        if secoes.sessoes > 0 { SecaoClaude(sessoes: fontes.claude) }
                        if secoes.tocando { LinhaTocando(tocando: tocando) }
                        if secoes.linhas > 0 { Lista(mural: mural, estado: estado) }
                        if secoes.apps { LinhaApps(mac: fontes.mac) }
                        if secoes.bandeja { FileiraDaBandeja(bandeja: bandeja, alvo: estado.alvo) }
                        }
                    }
                    .padding(.top, g.faixaDoTopo + 8)
                }
            }
            .padding(.horizontal, forma.orelha)
            .transition(.blurReplace)
        }
        .frame(width: tamanho.width, height: tamanho.height)
        .clipShape(contorno)
        // Só recebe com a ilha aberta: fechada, a janela ignora o mouse e o arraste passa direto.
        .dropDestination(for: URL.self) { urls, _ in
            bandeja.arrastando = false
            return bandeja.adicionar(urls) > 0  // um link da web não é arquivo: o arraste volta para a origem
        } isTargeted: { estado.alvo = $0 }
        .shadow(color: .black.opacity(forma == .aberta ? 0.4 : 0), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        // Abrir com um pouco de mola, fechar sem: a ilha "cai" do notch e volta para dentro dele sem quicar.
        .animation(forma == .repouso || forma == .compacta
                   ? .spring(response: 0.34, dampingFraction: 0.92)
                   : .spring(response: 0.44, dampingFraction: 0.74), value: forma)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mural.atividades.map(\.id))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mural.avisos.map(\.id))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: bandeja.arquivos.count)
        .animation(.smooth(duration: 0.2), value: estado.alvo)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: tocando.app)
        .animation(.smooth(duration: 0.3), value: tocando.metadados)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: fontes.claude.sessoes)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: secoes.hoje)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: secoes.apps)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: secoes.interesse)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: estado.aba)
        .animation(.smooth(duration: 0.25), value: privacidade)
    }
}

/// O contorno do notch: orelhas côncavas no topo, que fundem a ilha com a borda da tela,
/// e cantos de baixo arredondados. Os dois raios animam entre os estados.
struct FormaIlha: Shape {
    var orelha: CGFloat
    var raio: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(orelha, raio) }
        set { orelha = newValue.first; raio = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let o = min(orelha, r.width / 4)
        let raio = max(0, min(raio, (r.width - 2 * o) / 2, r.height - o))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + o, y: r.minY + o), control: CGPoint(x: r.minX + o, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX + o, y: r.maxY), tangent2End: CGPoint(x: r.maxX - o, y: r.maxY), radius: raio)
        p.addArc(tangent1End: CGPoint(x: r.maxX - o, y: r.maxY), tangent2End: CGPoint(x: r.maxX - o, y: r.minY + o), radius: raio)
        p.addLine(to: CGPoint(x: r.maxX - o, y: r.minY + o))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - o, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// O topo da ilha aberta: as abas e a engrenagem, para achar os atalhos e os Ajustes sem ir à barra de menus.
private struct Cabecalho: View {
    let estado: EstadoIlha
    let mural: Mural

    var body: some View {
        HStack(spacing: 4) {
            aba("Início", "house.fill", .inicio)
            aba("Atalhos", "command", .atalhos)
            Spacer(minLength: 0)
            if estado.aba == .inicio && !mural.atividades.isEmpty {
                // Duas sessões do Claude terminaram e os avisos ficaram: um clique tira todos.
                Button { mural.limpar() } label: {
                    Label("Limpar", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(.white.opacity(0.1)))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text("Tirar todos os avisos da ilha"))
                .transition(.opacity)
            }
            Button("Ajustes", systemImage: "gearshape.fill") { Kizami.shared.abrirAjustes() }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(.rect)
                .help(Text("Ajustes"))
        }
        .padding(.horizontal, 10)
        .frame(height: Geometria.alturaCabecalho)
    }

    private func aba(_ nome: LocalizedStringKey, _ simbolo: String, _ valor: EstadoIlha.Aba) -> some View {
        let escolhida = estado.aba == valor
        return Button { estado.aba = valor } label: {
            Label(nome, systemImage: simbolo)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(.white.opacity(escolhida ? 0.16 : 0)))
                .foregroundStyle(escolhida ? .primary : .secondary)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// A faixa de cima da ilha aberta: o próximo evento à esquerda, o tempo à direita. Cada um some sozinho
/// quando não tem o que mostrar (sem acesso à agenda, sem cidade).
private struct LinhaHoje: View {
    let agenda: Agenda
    let tempo: Tempo

    var body: some View {
        HStack(spacing: 8) {
            ChipAgenda(agenda: agenda)
            Spacer(minLength: 0)
            ChipTempo(tempo: tempo).fixedSize()  // a máxima e a mínima não podem virar reticências
        }
        .padding(.horizontal, 14)
        .frame(height: Geometria.alturaHoje)
    }
}

/// O que está tocando: a miniatura, o título e o artista (ou o nome do app, quando o player não conta a faixa).
private struct LinhaTocando: View {
    let tocando: TocandoAgora

    var body: some View {
        HStack(spacing: 12) {
            Miniatura(tocando: tocando, lado: 40, raio: 9)
            VStack(alignment: .leading, spacing: 1) {
                // verbatim: título e artista vêm do player e não podem virar Markdown nem chave de tradução.
                Text(verbatim: tocando.metadados?.titulo ?? tocando.nomeDoApp)
                    .font(.callout.weight(.semibold))
                Text(verbatim: tocando.metadados?.titulo == nil
                     ? String(localized: "Tocando agora")
                     : [tocando.metadados?.artista, tocando.nomeDoApp].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .contentTransition(.opacity)
            Spacer(minLength: 8)
            if let app = tocando.app, Controle.sabeControlar(app) {
                Controles(app: app, pausado: tocando.pausado)
            } else {
                Barras(altura: 16)  // navegador: sem comando público, só o sinal de que há som
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Geometria.alturaTocando)
    }
}

/// Anterior, tocar ou pausar, próxima. A ilha aberta aceita clique sem ativar o Kizami (painel que não vira key):
/// o foco continua no app em que a pessoa está.
private struct Controles: View {
    let app: String
    let pausado: Bool

    var body: some View {
        HStack(spacing: 2) {
            botao("Anterior", "backward.fill", .anterior, tamanho: 13)
            botao(pausado ? "Tocar" : "Pausar", pausado ? "play.fill" : "pause.fill", .alternar, tamanho: 18)
                .contentTransition(.symbolEffect(.replace))
            botao("Próxima", "forward.fill", .proxima, tamanho: 13)
        }
    }

    private func botao(_ nome: LocalizedStringKey, _ simbolo: String, _ acao: Controle.Acao, tamanho: CGFloat) -> some View {
        Button(nome, systemImage: simbolo) { Controle.enviar(acao, app: app) }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: tamanho, weight: .semibold))
            .frame(width: 30, height: 30)
            .contentShape(.rect)
            .help(Text(nome))
    }
}

/// A capa, quando o player dá; senão o ícone do app que está tocando.
private struct Miniatura: View {
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
        .animation(.smooth(duration: 0.35), value: tocando.capa)
    }
}

/// Equalizador de enfeite: as barras não leem o som (isso pediria gravar a saída), só mostram que há som.
private struct Barras: View {
    let altura: CGFloat

    var body: some View {
        // Enfeite: 15 quadros por segundo bastam e custam metade de 30, em cada monitor.
        TimelineView(.animation(minimumInterval: 1 / 15)) { contexto in
            let t = contexto.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .frame(width: 3, height: altura * (0.3 + 0.7 * abs(sin(t * (2.6 + Double(i) * 0.7) + Double(i) * 1.3))))
                }
            }
            .frame(height: altura)
        }
        .foregroundStyle(.white.opacity(0.85))
    }
}

/// Fechada: uma coisa em cada asa, com a mesma folga em cima, embaixo e do lado. Assim o conteúdo acompanha
/// o canto arredondado de baixo, em vez de encostar na borda (com 22 pt de altura no monitor externo, encostava).
private struct Asas<Esquerda: View, Direita: View>: View {
    let altura: CGFloat
    let esquerda: Esquerda
    let direita: Direita

    init(altura: CGFloat, @ViewBuilder esquerda: () -> Esquerda, @ViewBuilder direita: () -> Direita) {
        self.altura = altura
        self.esquerda = esquerda()
        self.direita = direita()
    }

    var body: some View {
        let lado = ladoDaAsa(altura)
        HStack(spacing: 0) {
            esquerda.frame(minWidth: lado, maxHeight: lado, alignment: .leading)
            Spacer(minLength: 0)
            direita.frame(minWidth: lado, maxHeight: lado)
        }
        .padding(.horizontal, (altura - lado) / 2 + 2)  // um pouco mais que em cima: o canto curva para dentro
        .frame(height: altura)
    }
}

/// O lado do conteúdo de uma asa: 20 pt no notch de 32, sempre com 6 pt de folga em cima e embaixo.
private func ladoDaAsa(_ altura: CGFloat) -> CGFloat { min(20, altura - 12) }

private struct Simbolo: View {
    let nome: String
    let cor: Color
    let chegada: Date?

    var body: some View {
        Image(systemName: nome)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(cor)
            .symbolEffect(.bounce, value: chegada)
    }
}

/// Um ponto para um item; o número para mais de um.
private struct Contador: View {
    let total: Int
    let cor: Color

    var body: some View {
        if total > 1 {
            Text(verbatim: "\(total)").font(.caption.weight(.bold)).monospacedDigit()
                .contentTransition(.numericText())
        } else {
            Circle().fill(cor).frame(width: 7, height: 7)
        }
    }
}

/// A bandeja aberta: os arquivos numa fileira (arrastáveis para fora) e as ações ao lado.
/// Vazia, durante um arraste, é só a área de soltar.
private struct FileiraDaBandeja: View {
    let bandeja: Bandeja
    let alvo: Bool

    var body: some View {
        Group {
            if bandeja.arquivos.isEmpty {
                Label("Solte aqui para guardar", systemImage: "tray.and.arrow.down")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(alvo ? .primary : .secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(.white.opacity(alvo ? 0.8 : 0.3))
                    }
            } else {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(bandeja.arquivos, id: \.self) { url in
                                ArquivoNaBandeja(url: url, bandeja: bandeja)
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                    }
                    VStack(spacing: 6) {
                        Button("Enviar por AirDrop", systemImage: "square.and.arrow.up") {
                            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: bandeja.arquivos)
                        }
                        Button("Esvaziar a bandeja", systemImage: "xmark") { bandeja.esvaziar() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
                .background {
                    RoundedRectangle(cornerRadius: 16).fill(.white.opacity(alvo ? 0.14 : 0.06))
                }
            }
        }
        .frame(height: Geometria.alturaBandeja)
        .padding(.horizontal, 10)
    }
}

/// Um arquivo da bandeja: arrastar leva para outro app (como arrastar do Finder), clique duplo abre.
private struct ArquivoNaBandeja: View {
    let url: URL
    let bandeja: Bandeja

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 32, height: 32)
            // verbatim: nome de arquivo não pode virar Markdown nem chave de tradução.
            Text(verbatim: url.lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 58)
        .padding(.vertical, 6)
        .contentShape(.rect)
        .help(url.lastPathComponent)
        // Oferece o conteúdo do arquivo, não o endereço: o destino recebe uma cópia. Com o endereço (`.draggable(url)`),
        // o Finder moveria o original ao soltar numa pasta do mesmo disco.
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(url) }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Tirar da bandeja") { bandeja.remover(url) }
        }
    }
}

/// O aviso: ícone, título e detalhe numa linha, centrados abaixo do notch.
private struct LinhaDeAviso: View {
    let atividade: Atividade

    var body: some View {
        HStack(spacing: 8) {
            Icone(atividade: atividade)
            // verbatim: o texto vem de fora e não pode virar Markdown nem chave de tradução.
            Text(verbatim: atividade.titulo).font(.callout.weight(.semibold))
            if let detalhe = atividade.detalhe {
                Text(verbatim: detalhe).font(.callout).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
    }
}

/// Aberta: as três mais recentes; com mais de três, duas e a linha "mais N" no lugar da terceira.
private struct Lista: View {
    let mural: Mural
    let estado: EstadoIlha

    var body: some View {
        let atividades = mural.atividades
        let visiveis = atividades.count > Geometria.maximoLinhas ? Geometria.maximoLinhas - 1 : Geometria.maximoLinhas
        VStack(alignment: .leading, spacing: Geometria.espacoLinha) {
            ForEach(atividades.prefix(visiveis)) { atividade in
                HStack(spacing: 10) {
                    Icone(atividade: atividade).frame(width: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: atividade.titulo).font(.callout.weight(.semibold))
                        if let detalhe = atividade.detalhe {
                            Text(verbatim: detalhe).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    if estado.linhaSobCursor == atividade.id {
                        Button("Tirar da ilha", systemImage: "xmark.circle.fill") { mural.remover(id: atividade.id) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .help(Text("Tirar da ilha"))
                    } else if let chegada = atividade.chegada {
                        Text(chegada, style: .relative).font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                    }
                }
                .onHover { dentro in
                    if dentro { estado.linhaSobCursor = atividade.id }
                    else if estado.linhaSobCursor == atividade.id { estado.linhaSobCursor = nil }
                }
                .frame(height: Geometria.alturaLinha)
                .contentShape(.rect)
                // Só as do próprio Kizami abrem algo (a sessão do Claude, o jogo, a reunião, o app do emblema).
                .onTapGesture { mural.abrir(atividade.id) }
                .transition(.blurReplace)
            }
            if atividades.count > visiveis {
                Text(String(localized: "mais \(atividades.count - visiveis)"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: Geometria.alturaLinha)
                    .padding(.leading, 32)  // alinhado com os títulos, depois da coluna dos ícones
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct Icone: View {
    let atividade: Atividade

    var body: some View {
        Image(systemName: atividade.simbolo ?? "bell.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(cor(atividade))
            .symbolEffect(.bounce, value: atividade.chegada)
    }
}

private func cor(_ atividade: Atividade) -> Color {
    switch atividade.cor {
    case "vermelho": .red
    case "laranja": .orange
    case "amarelo": .yellow
    case "verde": .green
    case "azul": .blue
    case "roxo": .purple
    case "rosa": .pink
    case "cinza": .gray
    default: .white
    }
}
