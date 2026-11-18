import SwiftUI

/// O próximo jogo ou corrida num quadrado: quando (ou o placar ao vivo, grande) e o nome. Clique: a página na ESPN.
struct WidgetInteresse: View {
    let interesses: Interesses
    let estado: EstadoIlha

    var body: some View {
        if let evento = interesses.proximos.first {
            let placar = interesses.aoVivo.first { $0.eDo(evento) }
            Quadro(id: "interesse", estado: estado, acao: { interesses.abrir(evento) }) {
                Cabeca(rotulo: placar == nil ? Text("A seguir") : Text("Ao vivo"),
                       simbolo: evento.fonte.simbolo, cor: Self.cor(evento.fonte),
                       ponto: placar == nil ? nil : .red)
                // verbatim: siglas, placar, situação e título vêm da ESPN ou de um calendário de fora.
                if let placar {
                    Text(verbatim: placar.texto).font(Tipo.numeroMedio).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(verbatim: placar.situacao.isEmpty ? evento.titulo : placar.situacao)
                        .font(Tipo.corpo).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    // Por minuto: "em 12 min" precisa andar sozinho, sem os Interesses publicarem nada.
                    TimelineView(.everyMinute) { contexto in
                        Text(verbatim: EventoInteresse.quando(evento, agora: contexto.date))
                            .font(Tipo.numeroMedio).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Text(verbatim: evento.titulo).font(Tipo.corpo).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                // O próximo de outra fonte seguida, em pequeno (a F1 em cima, os Bills embaixo): os dois que a pessoa
                // segue de relance, sem um esconder o outro.
                if let outro = interesses.proximos.first(where: { $0.fonte != evento.fonte }) {
                    TimelineView(.everyMinute) { contexto in
                        HStack(spacing: 4) {
                            Image(systemName: outro.fonte.simbolo).foregroundStyle(Self.cor(outro.fonte))
                            Text(verbatim: "\(outro.titulo) · \(EventoInteresse.quando(outro, agora: contexto.date))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11)).monospacedDigit().lineLimit(1)
                    }
                }
            }
            .help(evento.link == nil ? "" : String(localized: "Abrir na ESPN"))
        }
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
