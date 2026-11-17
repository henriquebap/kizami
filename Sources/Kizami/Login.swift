import Observation
import ServiceManagement

/// Abrir o Kizami no login, pelo `SMAppService` (sem LaunchAgent à mão). O estado vem do sistema a cada leitura:
/// a pessoa pode tirar o Kizami em Ajustes do Sistema › Itens de Início, e a seção tem de mostrar isso.
@MainActor @Observable
final class Login {
    private(set) var estado = SMAppService.mainApp.status
    private(set) var falhou = false

    var ligado: Bool { estado == .enabled }
    /// O macOS pede para a pessoa aprovar em Itens de Início (aparece um aviso dele).
    var precisaAprovar: Bool { estado == .requiresApproval }

    /// `ligar`: o valor que a pessoa pediu no toggle, não o inverso do estado guardado, que pode estar velho
    /// (desligado em Itens de Início com os Ajustes abertos).
    func alternar(para ligar: Bool) {
        conferir()
        guard ligar != ligado else { return }
        do {
            if ligar { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            falhou = false
        } catch {
            falhou = true
            registro.notice("login: não deu para mudar o item de início")
        }
        conferir()
    }

    func conferir() { estado = SMAppService.mainApp.status }

    func abrirItensDeInicio() { SMAppService.openSystemSettingsLoginItems() }
}
