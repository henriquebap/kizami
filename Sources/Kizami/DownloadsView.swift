import SwiftUI

/// A seção dos Ajustes: ligar os downloads, que pedem acesso à pasta Downloads, e o que acontece se o macOS negar.
struct AjustesDownloads: View {
    let downloads: Downloads

    init(downloads: Downloads) {
        self.downloads = downloads
    }

    var body: some View {
        Section("Downloads") {
            Toggle("Mostrar os downloads em andamento",
                   isOn: Binding(get: { downloads.ligado }, set: { downloads.ligado = $0 }))
            if downloads.ligado && downloads.acesso == .negado {
                Text("Sem acesso à pasta Downloads. Libere o Kizami em Arquivos e Pastas, nos Ajustes do Sistema, e ligue de novo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Abrir os Ajustes do Sistema") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Text("Chrome, Safari e Firefox: o Kizami só olha a pasta Downloads, nunca move nem abre um arquivo sem o seu clique.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
