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
            .accessibilityLabel(WidgetMac.descricaoPrivacidade(microfone: microfone, camera: mac.camera))
        }
    }
}

/// O Mac num quadrado: a bateria num anel, os apps com emblema no Dock (clique abre o app) e quem está no
/// microfone e na câmera.
struct WidgetMac: View {
    let mac: Mac
    let estado: EstadoIlha

    var body: some View {
        Quadro(id: "mac", estado: estado) {
            Cabeca(rotulo: Text(verbatim: "Mac"))
            Valor {
                if let bateria = mac.bateria { AnelDaBateria(bateria: bateria) }
                ForEach(mac.emblemas.prefix(mac.bateria == nil ? 4 : 3)) { emblema in  // mais que isso não cabe no quadro
                    Button { Mac.ativar(emblema.bundle) } label: {
                        Self.icone(emblema.bundle)
                            .frame(width: 22, height: 22)
                            .overlay(alignment: .topTrailing) {
                                Text(verbatim: emblema.rotulo)  // vem do Dock: dado, nunca chave de tradução
                                    .font(.system(size: 9, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 3)
                                    .frame(minWidth: 14, minHeight: 14)
                                    .background(Capsule().fill(.red))
                                    .offset(x: 6, y: -5)
                            }
                    }
                    .buttonStyle(EstiloBotao())
                    .help(Text(verbatim: emblema.nome))
                }
                Spacer(minLength: 0)
                privacidade
            }
            if let bateria = mac.bateria {
                Detalhe {
                    Text(verbatim: "\(bateria.porcento)%")
                    Text(bateria.carregando ? "carregando" : bateria.ligadaNaTomada ? "na tomada" : "bateria")
                }
            }
        }
    }

    @ViewBuilder private var privacidade: some View {
        let microfone = mac.microfone.first
        if microfone != nil || mac.camera {
            VStack(spacing: 4) {
                if mac.camera { Image(systemName: "video.fill").foregroundStyle(.green) }
                if let microfone {
                    Button { Mac.ativar(microfone) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "mic.fill").foregroundStyle(.orange)
                            Self.icone(microfone).frame(width: 16, height: 16)
                        }
                    }
                    .buttonStyle(EstiloBotao())
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

/// A bateria num anel: verde carregando ou na tomada, vermelho com 20% ou menos fora da tomada.
private struct AnelDaBateria: View {
    let bateria: Bateria

    var body: some View {
        let cor: Color = bateria.carregando || bateria.ligadaNaTomada ? .green
            : bateria.porcento <= 20 ? .red : .white
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(bateria.porcento, 0), 100)) / 100)
                .stroke(cor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(bateria.porcento)").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(width: Painel.alturaValor, height: Painel.alturaValor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(bateria.porcento)%"))
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
