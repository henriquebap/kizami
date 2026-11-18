import AppKit
import SwiftUI

/// Os atalhos do Mac num clique, para quem não decorou as teclas: a ilha mostra a combinação embaixo de cada um.
/// As capturas e o bloqueio são as próprias teclas do sistema (respeitam onde a pessoa guarda as capturas);
/// mandar teclas pede a permissão de Acessibilidade, pedida no primeiro clique.
// ponytail: usa as teclas padrão do macOS. Quem trocou o atalho nos Ajustes do Sistema precisa trocar aqui também.
enum Atalho: CaseIterable, Identifiable {
    case telaInteira, area, capturaEGravacao, janelas, emojis, bloquear

    var id: Self { self }

    var nome: LocalizedStringKey {
        switch self {
        case .telaInteira: "Tela"
        case .area: "Área"
        case .capturaEGravacao: "Gravar"
        case .janelas: "Janelas"
        case .emojis: "Emojis"
        case .bloquear: "Bloquear"
        }
    }

    /// A explicação no balão do cursor.
    var ajuda: LocalizedStringKey {
        switch self {
        case .telaInteira: "Captura da tela inteira"
        case .area: "Captura de uma área (ou da janela, com espaço)"
        case .capturaEGravacao: "Captura e gravação de tela, com opções"
        case .janelas: "Mission Control: todas as janelas"
        case .emojis: "Emojis e símbolos, no app em que você está"
        case .bloquear: "Bloquear a tela"
        }
    }

    var simbolo: String {
        switch self {
        case .telaInteira: "macwindow.on.rectangle"
        case .area: "rectangle.dashed"
        case .capturaEGravacao: "record.circle"
        case .janelas: "rectangle.3.group"
        case .emojis: "face.smiling"
        case .bloquear: "lock.fill"
        }
    }

    /// As teclas, como o macOS escreve nos menus. Nome de tecla não se traduz.
    var teclas: String {
        switch self {
        case .telaInteira: "⇧⌘3"
        case .area: "⇧⌘4"
        case .capturaEGravacao: "⇧⌘5"
        case .janelas: "⌃↑"
        case .emojis: "⌃⌘␣"
        case .bloquear: "⌃⌘Q"
        }
    }

    /// Tecla virtual (Carbon `kVK_*`) e modificadores. Mission Control abre pelo app: a seta precisa das flags de
    /// tecla de função, e o app não pede permissão nenhuma.
    private var combinacao: (CGKeyCode, CGEventFlags)? {
        switch self {
        case .telaInteira: (0x14, [.maskShift, .maskCommand])
        case .area: (0x15, [.maskShift, .maskCommand])
        case .capturaEGravacao: (0x17, [.maskShift, .maskCommand])
        case .emojis: (0x31, [.maskControl, .maskCommand])
        case .bloquear: (0x0C, [.maskControl, .maskCommand])
        case .janelas: nil
        }
    }

    /// Roda o atalho. Sem a permissão, pede (o macOS mostra o aviso uma vez) e deixa na ilha como liberar.
    @MainActor func executar(mural: Mural) {
        guard let (tecla, modificadores) = combinacao else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                                               configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return
        }
        guard CGPreflightPostEventAccess() else {
            CGRequestPostEventAccess()
            mural.receber(Atividade(id: "kizami-atalhos", titulo: String(localized: "Atalhos pedem Acessibilidade"),
                                    detalhe: String(localized: "Clique para liberar o Kizami"), simbolo: "keyboard",
                                    cor: "laranja", expira: 20)) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            registro.notice("atalhos: sem permissão para mandar teclas")
            return
        }
        let fonte = CGEventSource(stateID: .hidSystemState)
        for apertada in [true, false] {
            let evento = CGEvent(keyboardEventSource: fonte, virtualKey: tecla, keyDown: apertada)
            evento?.flags = modificadores
            evento?.post(tap: .cghidEventTap)
        }
        registro.info("atalho executado")
    }
}

/// A aba de atalhos da ilha aberta: um botão por atalho, com o nome e as teclas embaixo, para ir aprendendo.
struct GradeDeAtalhos: View {
    let estado: EstadoIlha
    let mural: Mural

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Atalho.allCases) { atalho in
                Button {
                    // A ilha recolhe antes: a captura não pode sair com ela aberta por cima, nem a mira começar em cima dela.
                    estado.recolher = true
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        atalho.executar(mural: mural)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: atalho.simbolo).font(.system(size: 17, weight: .medium)).frame(height: 22)
                        Text(atalho.nome).font(.caption2.weight(.semibold))
                        Text(verbatim: atalho.teclas).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .vidroDeControle(raio: 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(Text(atalho.ajuda))
            }
            // Não é tecla: troca a aba pela câmera, para se ver antes de uma chamada. Desliga ao fechar a ilha.
            Button { estado.aba = .espelho } label: {
                VStack(spacing: 3) {
                    Image(systemName: "person.crop.square").font(.system(size: 17, weight: .medium)).frame(height: 22)
                    Text("Espelho").font(.caption2.weight(.semibold))
                    Text(verbatim: " ").font(.system(size: 9))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .vidroDeControle(raio: 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(Text("Ver a câmera antes de uma chamada"))
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: Geometria.alturaAtalhos)
    }
}

/// A tecla de play/pause do teclado, para o player do navegador, que não tem AppleScript. O macOS entrega a tecla
/// ao app que está tocando ("Tocando agora"). Mandar tecla pede Acessibilidade, a mesma da aba Atalhos.
enum TeclaDeMidia {
    /// `NX_KEYTYPE_PLAY` em `IOKit/hidsystem/ev_keymap.h`.
    private static let play = 16

    @MainActor static func tocarOuPausar() {
        guard CGPreflightPostEventAccess() else {
            CGRequestPostEventAccess()
            registro.notice("mídia: sem permissão para mandar teclas")
            return
        }
        // Tecla de mídia é um evento "definido pelo sistema" (subtipo 8): a tecla nos bits altos de data1 e
        // 0xA (apertou) ou 0xB (soltou) logo abaixo. Não existe CGEvent público para ela, só o NSEvent.
        for apertada in [true, false] {
            let estado = apertada ? 0xA : 0xB
            let evento = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(estado << 8)),
                                            timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                            data1: (play << 16) | (estado << 8), data2: -1)
            evento?.cgEvent?.post(tap: .cghidEventTap)
        }
        registro.info("mídia: play/pause enviado")
    }
}
