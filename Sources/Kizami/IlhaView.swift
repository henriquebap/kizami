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
    let kanji: PonteKanji
    let cronometro: Cronometro
    let copiados: Copiados
    let espelho: Espelho
    let personalizacao: Personalizacao
    let atalhosApple: AtalhosApple
}

extension Aba {
    /// O nome no cabeçalho e nos Ajustes. Literais, para a extração das strings achar cada um.
    var nome: LocalizedStringKey {
        switch self {
        case .inicio: "Início"
        case .hoje: "Hoje"
        case .timer: "Timer"
        case .copiados: "Copiados"
        case .atalhos: "Atalhos"
        case .kanji: "Kanji"
        case .espelho: "Espelho"
        }
    }
}

/// A vez de cada coisa nas asas, na ordem que a pessoa escolheu (`Personalizacao.asa`). Por padrão o timer correndo
/// vem primeiro: só uma atividade alta ou urgente, nos primeiros 2 min (`Mural.importante`), passa na frente dele.
/// Pausado, o timer sai da asa (fica na aba).
@MainActor func asaAtual(_ f: Fontes) -> Asa {
    Personalizacao.asa(ordem: f.personalizacao.asas, importante: f.mural.importante) { asa in
        switch asa {
        case .atividades: !f.mural.atividades.isEmpty
        case .timer: f.cronometro.ativo && !f.cronometro.pausado
        case .reuniao: f.agenda.emBreve != nil
        case .placar: !f.interesses.aoVivo.isEmpty
        case .tocando: f.tocando.app != nil
        case .privacidade: !f.mac.microfone.isEmpty || f.mac.camera
        case .bandeja: !f.bandeja.arquivos.isEmpty
        case .nada: false
        }
    }
}

/// O tamanho da ilha fechada agora: o aviso, as asas ou o repouso. A janela mede a área do hover com a mesma conta.
@MainActor func tamanhoFechado(_ g: Geometria, _ f: Fontes) -> CGSize {
    if !f.mural.avisos.isEmpty { return g.aviso(linhas: f.mural.avisos.count) }
    return switch asaAtual(f) {
    case .atividades: g.compacta(icones: f.mural.destaques.count)
    case .timer, .reuniao: g.compacta(icones: 2)  // "24:59" ou "10 min" não cabe na asa de um ícone
    case .placar: g.compacta(icones: 3)  // "BUF 14" de um lado, "7 KC" do outro; na F1, "1 NOR" e "2 VER": cabe qualquer um da vez
    case .tocando, .privacidade, .bandeja: g.compacta
    case .nada: g.repouso
    }
}

/// O tamanho da ilha aberta na aba escolhida. A janela mede a área do hover com a mesma conta.
/// Com um item expandido, o Início é o cabeçalho e ele.
@MainActor func tamanhoAberto(_ g: Geometria, _ estado: EstadoIlha, _ f: Fontes) -> CGSize {
    switch estado.aba {
    case .inicio:
        switch expansaoAtual(estado, f) {
        case .agenda: g.abertaComAba(alturaDaAgendaExpandida(estado, f.agenda))
        case .musica: g.abertaComAba(Geometria.alturaMusica(barra: f.tocando.app.map(Controle.sabeControlar) == true))
        case nil: g.aberta(secoesAtuais(f))
        }
    case .atalhos: g.abertaComAba(Geometria.alturaComFileira(f.atalhosApple.escolhidos.count))
    case .kanji: g.abertaComAba(AbaKanji.altura(skills: f.kanji.skills.count))
    case .hoje: g.abertaComAba(Geometria.alturaDoDia(eventos: f.agenda.hoje.count))
    case .timer: g.abertaAtalhos
    case .copiados: g.abertaComAba(Geometria.alturaDaLista(itens: f.copiados.itens.count))
    case .espelho: g.abertaComAba(AbaEspelho.altura)
    }
}

/// O item expandido que ainda dá para mostrar: a música parou, a agenda perdeu o acesso ou a pessoa foi para
/// outra aba, e o Início volta ao normal (a escolha fica para quando voltar).
@MainActor func expansaoAtual(_ estado: EstadoIlha, _ f: Fontes) -> EstadoIlha.Expansao? {
    guard estado.aba == .inicio else { return nil }
    return switch estado.expandido {
    case .agenda: f.agenda.acesso == .permitido ? .agenda : nil
    case .musica: f.tocando.app != nil ? .musica : nil
    case nil: nil
    }
}

/// As seções da ilha aberta agora. A janela mede a área do hover com a mesma conta.
/// Uma seção escondida nos Ajustes conta como vazia: some da ilha e da conta da altura juntas.
@MainActor func secoesAtuais(_ f: Fontes) -> Secoes {
    let p = f.personalizacao
    return Secoes(tocando: p.mostra(.tocando) && f.tocando.app != nil, atividades: f.mural.atividades.count,
                  arquivos: p.mostra(.bandeja) ? f.bandeja.arquivos.count : 0, arrastando: f.bandeja.arrastando,
                  sessoes: p.mostra(.claude) ? f.claude.sessoes.count : 0,
                  hoje: p.mostra(.hoje) && (f.agenda.proximo != nil || f.tempo.previsao != nil),
                  apps: p.mostra(.apps) && (!f.mac.emblemas.isEmpty || !f.mac.microfone.isEmpty || f.mac.camera || f.mac.bateria != nil),
                  interesse: p.mostra(.interesse) && !f.interesses.proximos.isEmpty,
                  semBandejaVazia: !p.mostra(.bandeja))
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
    private var cronometro: Cronometro { fontes.cronometro }
    /// O vidro do chip da agenda e da linha do que está tocando muda de forma para o do item expandido.
    @Namespace private var espaco

    var body: some View {
        let g = estado.geometria
        let secoes = secoesAtuais(fontes)
        let asa = asaAtual(fontes)
        let forma: Forma = estado.aberta ? .aberta
            : !mural.avisos.isEmpty ? .aviso
            : asa != .nada ? .compacta
            : .repouso
        let tamanho = forma == .aberta ? tamanhoAberto(g, estado, fontes) : tamanhoFechado(g, fontes)
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
                    if asa == .reuniao, let reuniao = fontes.agenda.emBreve {
                        Asas(altura: g.notch.height) {
                            Simbolo(nome: "calendar", cor: reuniao.cor.map { Color(red: $0.x, green: $0.y, blue: $0.z) } ?? .red,
                                    chegada: nil)
                        } direita: {
                            HStack(spacing: 4) {
                                IndicadorPrivacidade(mac: fontes.mac)
                                // Por minuto: a contagem anda sozinha entre as releituras da agenda.
                                TimelineView(.everyMinute) { contexto in
                                    Text(verbatim: Self.falta(reuniao.inicio, agora: contexto.date))
                                        .font(.caption.weight(.bold)).monospacedDigit()
                                }
                            }
                        }
                    } else if asa == .timer {
                        Asas(altura: g.notch.height) {
                            Simbolo(nome: cronometro.modo.simbolo, cor: .orange, chegada: nil)
                        } direita: {
                            HStack(spacing: 4) {
                                IndicadorPrivacidade(mac: fontes.mac)  // a câmera ligada não pode sumir atrás do timer
                                ContagemNaAsa(cronometro: cronometro)
                            }
                        }
                    } else if asa == .placar {
                        // Dois ao vivo: um de cada vez, trocando a cada 8 s só pelo relógio, sem consulta a mais. Com um só,
                        // o relógio quase não bate: nada muda na tela, e cada tique redesenharia a ilha.
                        let vez = fontes.interesses.aoVivo.count > 1 ? Placar.vezNaAsa : 3600
                        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: vez)) { contexto in
                            if let lados = Placar.daVez(fontes.interesses.aoVivo, agora: contexto.date)?.asa {
                                Asas(altura: g.notch.height) {
                                    Text(verbatim: lados.esquerda)  // verbatim: siglas e pontos vêm da ESPN
                                } direita: {
                                    HStack(spacing: 4) {
                                        IndicadorPrivacidade(mac: fontes.mac)
                                        Text(verbatim: lados.direita)
                                    }
                                }
                                .font(.caption.weight(.bold)).monospacedDigit()
                                .contentTransition(.numericText())
                            }
                        }
                    } else if asa == .atividades, let primeira = mural.destaques.first {
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
                    } else if asa == .tocando {
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
                        Cabecalho(estado: estado, mural: mural, personalizacao: fontes.personalizacao)
                        if estado.aba == .atalhos {
                            VStack(spacing: 6) {
                                GradeDeAtalhos(estado: estado, mural: mural)
                                if !fontes.atalhosApple.escolhidos.isEmpty {
                                    FileiraAtalhosApple(estado: estado, atalhos: fontes.atalhosApple)
                                }
                            }
                        } else if estado.aba == .hoje {
                            AbaHoje(agenda: fontes.agenda)
                        } else if estado.aba == .timer {
                            AbaTimer(estado: estado, cronometro: cronometro)
                        } else if estado.aba == .espelho {
                            AbaEspelho(estado: estado, espelho: fontes.espelho)
                        } else if estado.aba == .copiados {
                            AbaCopiados(estado: estado, copiados: fontes.copiados)
                        } else if estado.aba == .kanji {
                            AbaKanji(estado: estado, kanji: fontes.kanji, mural: mural)
                        } else {
                        GlassEffectContainer {
                            VStack(spacing: Geometria.espacoSecao) {
                                switch expansaoAtual(estado, fontes) {
                                case .agenda:
                                    AgendaExpandida(estado: estado, agenda: fontes.agenda, espaco: espaco) { alternar(.agenda) }
                                case .musica:
                                    MusicaExpandida(estado: estado, tocando: tocando, espaco: espaco) { alternar(.musica) }
                                case nil:
                                    if secoes.hoje {
                                        LinhaHoje(agenda: fontes.agenda, tempo: fontes.tempo, espaco: espaco) { alternar(.agenda) }
                                    }
                                    if secoes.interesse { LinhaInteresse(interesses: fontes.interesses) }
                                    if secoes.sessoes > 0 { SecaoClaude(sessoes: fontes.claude) }
                                    if secoes.tocando { LinhaTocando(tocando: tocando, espaco: espaco) { alternar(.musica) } }
                                    if secoes.linhas > 0 { Lista(mural: mural, estado: estado) }
                                    if secoes.apps { LinhaApps(mac: fontes.mac) }
                                    if secoes.bandeja { FileiraDaBandeja(bandeja: bandeja, alvo: estado.alvo) }
                                }
                            }
                        }
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
        .animation(Movimento.ou(forma == .repouso || forma == .compacta ? Movimento.fechar : Movimento.abrir), value: forma)
        .animation(Movimento.ou(Movimento.conteudo), value: mural.atividades.map(\.id))
        .animation(Movimento.ou(Movimento.conteudo), value: mural.avisos.map(\.id))
        .animation(Movimento.ou(Movimento.conteudo), value: bandeja.arquivos.count)
        .animation(Movimento.rapido, value: estado.alvo)
        .animation(Movimento.ou(Movimento.conteudo), value: tocando.app)
        .animation(Movimento.rapido, value: tocando.metadados)
        .animation(Movimento.ou(Movimento.conteudo), value: fontes.claude.sessoes)
        .animation(Movimento.ou(Movimento.conteudo), value: secoes.hoje)
        .animation(Movimento.ou(Movimento.conteudo), value: secoes.apps)
        .animation(Movimento.ou(Movimento.conteudo), value: secoes.interesse)
        .animation(Movimento.ou(Movimento.conteudo), value: estado.aba)
        .animation(Movimento.rapido, value: privacidade)
        .animation(Movimento.ou(Movimento.conteudo), value: asa)
    }
}

extension IlhaView {
    /// Expande o item, ou recolhe o que já está expandido. A agenda lê o mês só enquanto está expandida.
    private func alternar(_ item: EstadoIlha.Expansao) {
        let novo = estado.expandido == item ? nil : item
        withAnimation(Movimento.ou(Movimento.expandir)) {
            estado.expandido = novo
            estado.diaEscolhido = nil
            estado.mesInteiro = false
            fontes.agenda.mostrar(novo == .agenda ? Calendario.intervalo(de: .now, calendario: .current) : nil)
        }
    }

    /// "8 min" até a reunião, ou "agora" quando já começou: cabe na asa.
    static func falta(_ inicio: Date, agora: Date) -> String {
        let minutos = Int((inicio.timeIntervalSince(agora) / 60).rounded(.up))
        return minutos > 0 ? String(localized: "\(minutos) min") : String(localized: "agora")
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
    let personalizacao: Personalizacao
    /// A pílula de vidro da aba escolhida tem um id só: trocar de aba faz o vidro deslizar até a nova.
    @Namespace private var espaco

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(personalizacao.abas, id: \.self) { aba($0) }
                Spacer(minLength: 0)
                if estado.aba == .inicio && !mural.atividades.isEmpty {
                    // Duas sessões do Claude terminaram e os avisos ficaram: um clique tira todos.
                    Button { mural.limpar() } label: {
                        Label("Limpar", systemImage: "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .glassEffect(.regular, in: .capsule)
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
        }
        .padding(.horizontal, 10)
        .frame(height: Geometria.alturaCabecalho)
    }

    private func aba(_ valor: Aba) -> some View {
        let escolhida = estado.aba == valor
        let nome = valor.nome
        let simbolo = valor.simbolo
        // Seis abas e o Limpar não cabem com nome em 340 pt: só a escolhida mostra o nome, as outras o ícone.
        return Button { estado.aba = valor } label: {
            Group {
                if escolhida { Label(nome, systemImage: simbolo) } else { Label(nome, systemImage: simbolo).labelStyle(.iconOnly) }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, escolhida ? 10 : 7)
            .frame(height: 22)
            .glassEffect(escolhida ? .regular : .identity, in: .capsule)
            .glassEffectID(escolhida ? "aba" : valor.rawValue, in: espaco)
            .foregroundStyle(escolhida ? .primary : .secondary)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(Text(nome))
    }
}

/// A faixa de cima da ilha aberta: o próximo evento à esquerda, o tempo à direita. Cada um some sozinho
/// quando não tem o que mostrar (sem acesso à agenda, sem cidade).
private struct LinhaHoje: View {
    let agenda: Agenda
    let tempo: Tempo
    let espaco: Namespace.ID
    /// Clique no chip: a agenda expande no lugar. O "Entrar" dentro dele continua sendo só o botão.
    let aoClicar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if agenda.proximo != nil {
                ChipAgenda(agenda: agenda)
                    .padding(.horizontal, 8)
                    .vidro(id: "agenda", em: espaco)
                    .contentShape(.rect)
                    .onTapGesture(perform: aoClicar)
                    .accessibilityAddTraits(.isButton)
                    .transition(.blurReplace)
            }
            Spacer(minLength: 0)
            ChipTempo(tempo: tempo).fixedSize()  // a máxima e a mínima não podem virar reticências
        }
        .padding(.horizontal, 14)
        .frame(height: Geometria.alturaHoje)
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
                    // A alta ou urgente (o "Claude precisa de você") fica até alguém tirar: o ✕ dela não se esconde.
                    if atividade.peso >= 2 || estado.linhaSobCursor == atividade.id {
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
