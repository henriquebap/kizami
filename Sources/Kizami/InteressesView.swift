import SwiftUI

/// O próximo jogo ou corrida num quadrado, uma página por fonte seguida (Bills, F1…): passa com dois dedos no trackpad
/// ou nos pontos do canto. Cada página: quando (ou o placar ao vivo, grande) e o nome. Clique: a página na ESPN.
struct WidgetInteresse: View {
    @Bindable var interesses: Interesses
    let estado: EstadoIlha

    var body: some View {
        let eventos = interesses.proximos
        if let primeiro = eventos.first {
            let atual = eventos.first { $0.fonte == interesses.fonteNaBox } ?? primeiro
            Quadro(id: "interesse", estado: estado, acao: { interesses.abrir(atual) }) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(eventos, id: \.fonte) { evento in
                            pagina(evento).containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $interesses.fonteNaBox)
                .overlay(alignment: .bottomTrailing) {
                    if eventos.count > 1 { pontos(eventos, atual: atual) }
                }
            }
            .help(atual.link == nil ? "" : String(localized: "Abrir na ESPN"))
        }
    }

    private func pagina(_ evento: EventoInteresse) -> some View {
        let placar = interesses.aoVivo.first { $0.eDo(evento) }
        // Página da F1 num treino: a corrida no pé, para saber quando é a que importa.
        let corrida = evento.sessao == nil ? nil : interesses.principais.first { $0.fonte == evento.fonte }
        return VStack(alignment: .leading, spacing: 0) {
            Cabeca(rotulo: placar == nil ? Text("A seguir") : Text("Ao vivo"),
                   simbolo: evento.fonte.simbolo, cor: Self.cor(evento.fonte),
                   ponto: placar == nil ? nil : .red)
            // verbatim: siglas, placar, situação e título vêm da ESPN ou de um calendário de fora.
            TimelineView(.everyMinute) { contexto in
                Valor {
                    Text(verbatim: placar?.texto ?? EventoInteresse.quando(evento, agora: contexto.date))
                        .contentTransition(.numericText())
                }
            }
            Detalhe {
                Text(verbatim: placar.map { $0.situacao.isEmpty ? evento.titulo : $0.situacao }
                     ?? evento.sessao.map { "\($0) · \(evento.titulo)" } ?? evento.titulo)
            }
            Spacer(minLength: 0)
            if let corrida {
                TimelineView(.everyMinute) { contexto in
                    Rodape {
                        Image(systemName: "flag.checkered").foregroundStyle(Self.cor(corrida.fonte))
                        Text("Corrida")
                        // A hora não pode ser a parte cortada: é a única coisa que a linha diz.
                        Text(verbatim: EventoInteresse.quando(corrida, agora: contexto.date))
                            .foregroundStyle(.secondary).layoutPriority(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Um ponto por página; clicar num vai para ela. Área de 12 pt: o ponto de 5 sozinho seria difícil de acertar.
    private func pontos(_ eventos: [EventoInteresse], atual: EventoInteresse) -> some View {
        HStack(spacing: 0) {
            ForEach(eventos, id: \.fonte) { evento in
                Button {
                    withAnimation(Movimento.conteudo) { interesses.fonteNaBox = evento.fonte }
                } label: {
                    Circle().fill(evento.fonte == atual.fonte ? Color.primary : Color.secondary.opacity(0.5))
                        .frame(width: 5, height: 5)
                        .frame(width: 12, height: Painel.alturaRodape)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: evento.fonte.nome))
            }
        }
    }

    private static func cor(_ fonte: Seguido) -> Color {
        switch fonte {
        case .espnTime: .blue
        case .f1: .red
        case .ics: .purple
        case .categoria: .orange
        }
    }
}

/// O que a pessoa está digitando na seção Interesses. Classe observável porque o build não tem a macro `@State`.
@MainActor @Observable
final class FormularioInteresses {
    var liga = Liga.todas[0]
    var busca = ""
    var buscando = false
    var resultados: [Seguido] = []
    var nadaAchado = false
    var calendario = ""
    var calendarioInvalido = false
}

/// A seção Interesses do Form agrupado dos Ajustes: o que é seguido, a busca de times, a F1 e um calendário ICS.
struct AjustesInteresses: View {
    @Bindable var interesses: Interesses
    @Bindable var formulario: FormularioInteresses

    var body: some View {
        Section("Interesses") {
            ForEach(interesses.seguidos, id: \.self) { seguido in
                HStack {
                    Image(systemName: seguido.simbolo).frame(width: 20)
                    Text(verbatim: seguido.nome).lineLimit(1).truncationMode(.middle)  // verbatim: nome da ESPN ou host do usuário
                    Spacer()
                    Button("Remover", systemImage: "minus.circle.fill") { interesses.remover(seguido) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remover")
                }
            }
            Picker("Liga", selection: $formulario.liga) {
                ForEach(Liga.todas) { liga in Text(verbatim: liga.nome).tag(liga) }
            }
            HStack {
                TextField("Time", text: $formulario.busca).onSubmit(buscar)
                Button("Buscar", action: buscar)
                    .disabled(formulario.buscando || formulario.busca.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(formulario.resultados, id: \.self) { time in
                HStack {
                    Text(verbatim: time.nome)
                    Spacer()
                    if interesses.seguidos.contains(time) {
                        Text("Seguindo").foregroundStyle(.secondary)
                    } else {
                        Button("Seguir") { interesses.adicionar(time) }
                            .disabled(interesses.seguidos.count >= Interesses.maximoSeguidos)
                    }
                }
            }
            if formulario.nadaAchado {
                Text("Nenhum time encontrado, ou a rede falhou.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Fórmula 1", isOn: $interesses.segueF1)
            ForEach(Categoria.allCases, id: \.self) { categoria in
                Toggle(isOn: Binding(get: { interesses.seguidos.contains(.categoria(categoria)) },
                                     set: { $0 ? interesses.adicionar(.categoria(categoria)) : interesses.remover(.categoria(categoria)) })) {
                    Text(verbatim: categoria.nome)
                }
            }
            HStack {
                TextField("Calendário (link ICS ou webcal)", text: $formulario.calendario).onSubmit(adicionarCalendario)
                Button("Adicionar", action: adicionarCalendario)
                    .disabled(formulario.calendario.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if formulario.calendarioInvalido {
                Text("Use um link https ou webcal.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Lembra na semana do evento, na véspera e 1 hora antes. Jogos e corridas vêm da ESPN; F2, WEC e IMSA, de calendários públicos.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: formulario.liga) {
            formulario.resultados = []
            formulario.nadaAchado = false
        }
    }

    private func buscar() {
        let nome = formulario.busca.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty, !formulario.buscando else { return }
        formulario.buscando = true
        formulario.nadaAchado = false
        let liga = formulario.liga
        Task {
            let achados = await interesses.buscarTimes(nome, liga: liga)
            formulario.buscando = false
            // A pessoa pode ter trocado de liga enquanto a resposta vinha.
            guard formulario.liga == liga else { return }
            formulario.resultados = achados
            formulario.nadaAchado = achados.isEmpty
        }
    }

    private func adicionarCalendario() {
        guard let seguido = Seguido.calendario(formulario.calendario) else {
            formulario.calendarioInvalido = true
            return
        }
        interesses.adicionar(seguido)
        formulario.calendario = ""
        formulario.calendarioInvalido = false
    }
}
