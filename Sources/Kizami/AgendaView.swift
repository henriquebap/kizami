import SwiftUI

/// O próximo evento, à esquerda da faixa "Hoje": a cor do calendário, o título, quando começa e,
/// se houver link de reunião, o botão de entrar. Sem evento (ou sem permissão), não ocupa nada.
struct ChipAgenda: View {
    let agenda: Agenda

    var body: some View {
        if let evento = agenda.proximo {
            HStack(spacing: 8) {
                Capsule()
                    .fill(evento.cor.map { Color(red: $0.x, green: $0.y, blue: $0.z) } ?? .red)
                    .frame(width: 3, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    // verbatim: o título vem do convite de qualquer pessoa e não pode virar Markdown nem chave de tradução.
                    Text(verbatim: evento.titulo).font(.callout.weight(.semibold))
                    // Por minuto: "em 12 min" precisa andar sozinho, sem a Agenda publicar nada.
                    TimelineView(.everyMinute) { contexto in
                        Text(verbatim: Self.quando(evento, agora: contexto.date))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if evento.link != nil {
                    Button("Entrar") { agenda.entrar() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.green.opacity(0.85)))
                        .contentShape(.capsule)
                        .fixedSize()
                }
            }
            .frame(maxWidth: 200, maxHeight: Geometria.alturaHoje, alignment: .leading)  // cede espaço ao tempo, que não encolhe
            .transition(.blurReplace)
        }
    }

    /// Hora exata para o que está longe; contagem na última hora, quando "quanto falta" importa mais que "a que horas".
    private static func quando(_ evento: EventoAgenda, agora: Date) -> String {
        let falta = evento.inicio.timeIntervalSince(agora)
        if falta <= 0 { return String(localized: "agora") }
        if falta < 3600 { return String(localized: "em \(Int((falta / 60).rounded(.up))) min") }
        return evento.inicio.formatted(date: .omitted, time: .shortened)
    }
}
