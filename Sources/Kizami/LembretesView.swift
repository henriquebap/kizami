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
