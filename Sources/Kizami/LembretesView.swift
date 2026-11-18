import SwiftUI

/// A seção dos Ajustes: ligar os lembretes, que pedem acesso ao app Lembretes, e o que fazer se o macOS negar.
struct AjustesLembretes: View {
    let lembretes: Lembretes

    init(lembretes: Lembretes) {
        self.lembretes = lembretes
    }

    var body: some View {
        Section("Lembretes") {
            Toggle("Mostrar os lembretes de hoje",
                   isOn: Binding(get: { lembretes.ligado }, set: { lembretes.ligado = $0 }))
            if lembretes.ligado && lembretes.acesso == .negado {
                Text("Sem acesso aos Lembretes. Libere o Kizami nos Ajustes do Sistema e ligue de novo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Abrir os Ajustes do Sistema") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Text("Os atrasados e os de hoje primeiro, depois os sem data. O Kizami só marca um lembrete como concluído quando você clica.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Os lembretes de hoje (e os atrasados) num quadrado, com o círculo que marca como feito.
/// O "atrasado" depende da hora, e a lista só muda quando o app Lembretes muda: o relógio por minuto acerta o rótulo.
struct WidgetLembretes: View {
    let lembretes: Lembretes
    let estado: EstadoIlha

    var body: some View {
        Quadro(id: "lembretes", estado: estado) {
            Cabeca(rotulo: Text("Lembretes"), simbolo: "checklist", cor: .yellow)
            TimelineView(.everyMinute) { contexto in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(lembretes.proximos) { lembrete in  // até 3 (`Lembrete.maximo`): cabem no quadro
                        HStack(spacing: 6) {
                            Button("Marcar como feito", systemImage: "circle") { lembretes.concluir(lembrete.id) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(EstiloBotao())
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .help(Text("Marcar como feito"))
                            // verbatim: o título vem do app Lembretes.
                            Text(verbatim: lembrete.titulo).font(Tipo.corpo).lineLimit(1)
                            Spacer(minLength: 2)
                            if let quando = lembrete.quando(agora: contexto.date) {
                                Text(verbatim: quando).font(Tipo.legenda).monospacedDigit()
                                    .foregroundStyle(lembrete.atrasado(agora: contexto.date) ? .red : .secondary)
                            }
                        }
                        .frame(height: Painel.alturaDetalhe)
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}
