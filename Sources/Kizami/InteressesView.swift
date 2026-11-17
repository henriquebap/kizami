import SwiftUI

/// O próximo de cada fonte seguida, lado a lado (os Bills e a F1, por exemplo), no estilo da `Lista`.
/// Clicar num abre a página dele na ESPN. Sem evento, não mostra nada.
struct LinhaInteresse: View {
    let interesses: Interesses

    var body: some View {
        let eventos = interesses.proximos
        HStack(spacing: 6) {
            ForEach(eventos) { evento in
                HStack(spacing: 6) {
                    Image(systemName: evento.fonte.simbolo)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Self.cor(evento.fonte))
                    VStack(alignment: .leading, spacing: 0) {
                        // verbatim: o título vem da ESPN ou de um calendário de fora e não pode virar Markdown nem chave de tradução.
                        Text(verbatim: evento.titulo).font(.caption.weight(.semibold))
                        if let placar = interesses.aoVivo.first(where: { $0.eDo(evento) }) {
                            HStack(spacing: 4) {
                                Circle().fill(.red).frame(width: 5, height: 5)
                                    .accessibilityLabel(Text("Ao vivo"))
                                // verbatim: siglas, pilotos e situação vêm da ESPN.
                                Text(verbatim: placar.situacao.isEmpty ? placar.texto : "\(placar.texto) · \(placar.situacao)")
                                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                        } else {
                            // Por minuto: "em 12 min" precisa andar sozinho, sem os Interesses publicarem nada.
                            TimelineView(.everyMinute) { contexto in
                                Text(verbatim: EventoInteresse.quando(evento, agora: contexto.date))
                                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(eventos.count > 1 ? .regular : .identity, in: .rect(cornerRadius: 10, style: .continuous))
                .contentShape(.rect)
                .onTapGesture { interesses.abrir(evento) }  // a página do jogo, com escalação, placar e onde passa
                .help(evento.link == nil ? "" : String(localized: "Abrir na ESPN"))
                .transition(.blurReplace)
            }
        }
        .frame(height: Geometria.alturaLinha + 4)
        .padding(.horizontal, eventos.count > 1 ? 10 : 6)
    }

    private static func cor(_ fonte: Seguido) -> Color {
        switch fonte {
        case .espnTime: .blue
        case .f1: .red
        case .ics: .purple
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
            HStack {
                TextField("Calendário (link ICS ou webcal)", text: $formulario.calendario).onSubmit(adicionarCalendario)
                Button("Adicionar", action: adicionarCalendario)
                    .disabled(formulario.calendario.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if formulario.calendarioInvalido {
                Text("Use um link https ou webcal.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Lembra na semana do evento, na véspera e 1 hora antes. Jogos e corridas vêm da ESPN.")
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
