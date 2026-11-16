import AppKit
import SwiftUI

/// Os pontinhos do iPhone para a asa da ilha fechada: laranja com o microfone aberto, verde com a câmera ligada.
struct IndicadorPrivacidade: View {
    let mac: Mac

    var body: some View {
        let microfone = !mac.microfone.isEmpty
        if microfone || mac.camera {
            HStack(spacing: 3) {
                if mac.camera { Circle().fill(.green).frame(width: 6, height: 6) }
                if microfone { Circle().fill(.orange).frame(width: 6, height: 6) }
            }
            .frame(width: 20, height: 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LinhaApps.descricaoPrivacidade(microfone: microfone, camera: mac.camera))
        }
    }
}

/// Uma linha da ilha aberta: os apps com emblema no Dock, quem está no microfone e na câmera, e a bateria.
struct LinhaApps: View {
    let mac: Mac

    var body: some View {
        HStack(spacing: 10) {
            ForEach(mac.emblemas) { emblema in
                Button { Mac.ativar(emblema.bundle) } label: {
                    Self.icone(emblema.bundle)
                        .frame(width: 22, height: 22)
                        .overlay(alignment: .topTrailing) {
                            Text(verbatim: emblema.rotulo)  // vem do Dock: dado, nunca chave de tradução
                                .font(.system(size: 9, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .frame(minWidth: 13, minHeight: 13)
                                .background(Capsule().fill(.red))
                                .offset(x: 6, y: -4)
                        }
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: emblema.nome))
            }
            Spacer(minLength: 0)
            privacidade
            if let bateria = mac.bateria {
                HStack(spacing: 3) {
                    Image(systemName: Self.simbolo(bateria))
                        .symbolRenderingMode(.hierarchical)
                    Text(verbatim: "\(bateria.porcento)%")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(bateria.porcento <= 20 && !bateria.ligadaNaTomada ? .red : .white)
            }
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: Geometria.alturaLinha)
    }

    @ViewBuilder private var privacidade: some View {
        let microfone = mac.microfone.first
        if microfone != nil || mac.camera {
            HStack(spacing: 4) {
                if mac.camera { Image(systemName: "video.fill").foregroundStyle(.green) }
                if let microfone {
                    Image(systemName: "mic.fill").foregroundStyle(.orange)
                    Button { Mac.ativar(microfone) } label: { Self.icone(microfone).frame(width: 16, height: 16) }
                        .buttonStyle(.plain)
                }
            }
            .font(.system(size: 11))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.descricaoPrivacidade(microfone: microfone != nil, camera: mac.camera))
        }
    }

    static func descricaoPrivacidade(microfone: Bool, camera: Bool) -> String {
        [microfone ? String(localized: "Microfone em uso") : nil, camera ? String(localized: "Câmera em uso") : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// O ícone do app; sem app instalado no caminho, um quadrado genérico.
    static func icone(_ bundle: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
            } else {
                Image(systemName: "app.fill").resizable().foregroundStyle(.secondary)
            }
        }
        .aspectRatio(contentMode: .fit)
    }

    static func simbolo(_ bateria: Bateria) -> String {
        if bateria.carregando { return "battery.100percent.bolt" }
        return switch bateria.porcento {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// A seção dos Ajustes: os emblemas do Dock, que pedem Acessibilidade, e o resto, que não pede nada.
struct AjustesMac: View {
    let mac: Mac

    var body: some View {
        Section("Apps e Mac") {
            Toggle("Mostrar as mensagens não lidas do Dock",
                   isOn: Binding(get: { mac.emblemasLigados }, set: { mac.ligarEmblemas($0) }))
            if mac.emblemasLigados && !mac.acessibilidade {
                Text("Para ler os emblemas do Dock, o Kizami precisa de Acessibilidade. Libere nos Ajustes do Sistema e abra esta janela de novo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Abrir os Ajustes do Sistema") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Text("Microfone, câmera e bateria aparecem na ilha sem pedir permissão.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { mac.conferirAcesso() }
    }
}
