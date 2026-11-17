import AVFoundation
import os

/// O espelho: a câmera na ilha aberta, para a pessoa se ver antes de uma chamada. Só vídeo, nunca áudio, e a
/// imagem não sai da `AVCaptureVideoPreviewLayer`: a sessão não tem saída nenhuma, então nada é gravado nem enviado.
/// O acesso só é pedido quando a pessoa abre o espelho, e a câmera desliga assim que ele sai da tela.
@MainActor @Observable
final class Espelho {
    enum Acesso: Equatable { case naoPedido, permitido, negado, semCamera }

    private(set) var acesso: Acesso = .naoPedido
    /// A sessão está rodando de verdade (a fila da câmera avisa depois de ligar ou desligar).
    private(set) var ligado = false
    /// O que a ilha quer agora: o pedido de acesso pode voltar depois que a pessoa já fechou o espelho.
    private var querLigado = false
    private var pedindo = false
    private let camera = Camera()

    /// Para a `AVCaptureVideoPreviewLayer` da aba. Só a layer lê a sessão; quem mexe nela é a fila da `Camera`.
    var sessao: AVCaptureSession { camera.sessao }

    init() {}

    /// Idempotente: chamar de novo com a câmera ligada não faz nada.
    func ligar() {
        querLigado = true
        acesso = Self.acesso(status: AVCaptureDevice.authorizationStatus(for: .video),
                             temCamera: AVCaptureDevice.default(for: .video) != nil)
        switch acesso {
        case .permitido:
            aplicar()
        case .naoPedido:
            guard !pedindo else { return }
            pedindo = true
            Task {
                let permitido = await AVCaptureDevice.requestAccess(for: .video)
                pedindo = false
                acesso = permitido ? .permitido : .negado
                registro.info("espelho: acesso à câmera \(permitido ? "permitido" : "negado", privacy: .public)")
                aplicar()
            }
        case .negado, .semCamera:
            registro.notice("espelho: câmera indisponível (\(String(describing: self.acesso), privacy: .public))")
        }
    }

    /// Idempotente e seguro em qualquer ordem: a ilha chama ao fechar e ao trocar de aba, a aba chama ao sumir.
    func desligar() {
        querLigado = false
        aplicar()
    }

    private func aplicar() {
        camera.aplicar(querLigado && acesso == .permitido) { [weak self] rodando in
            guard let self, rodando != ligado else { return }
            ligado = rodando
            registro.info("espelho: câmera \(rodando ? "ligada" : "desligada", privacy: .public)")
        }
    }

    /// Regra pura: o que a aba mostra, a partir da permissão do macOS e de haver câmera.
    nonisolated static func acesso(status: AVAuthorizationStatus, temCamera: Bool) -> Acesso {
        guard temCamera else { return .semCamera }
        switch status {
        case .authorized: return .permitido
        case .notDetermined: return .naoPedido
        case .denied, .restricted: return .negado
        @unknown default: return .negado
        }
    }
}

/// A sessão e a fila serial que é a única a mexer nela: `startRunning` bloqueia (meio segundo ou mais) e não
/// pode rodar na main. `@unchecked Sendable` porque a `AVCaptureSession` não é Sendable; a garantia é a fila.
private final class Camera: @unchecked Sendable {
    let sessao = AVCaptureSession()
    private let fila = DispatchQueue(label: "io.github.henriquebap.kizami.espelho")
    /// O último pedido da ilha. Cada bloco na fila aplica o pedido mais recente, não o da hora em que foi
    /// enfileirado: abrir e fechar a ilha várias vezes seguidas não liga e desliga a câmera a cada vez.
    private let desejado = OSAllocatedUnfairLock(initialState: false)
    /// Só lido e escrito na fila.
    private var configurada = false

    func aplicar(_ ligar: Bool, aoTerminar: @escaping @MainActor @Sendable (Bool) -> Void) {
        desejado.withLock { $0 = ligar }
        fila.async { [self] in
            if desejado.withLock({ $0 }) {
                if configurar(), !sessao.isRunning { sessao.startRunning() }
            } else {
                if sessao.isRunning { sessao.stopRunning() }
                // Solta a câmera: na próxima vez pega a padrão de novo (a do iPhone ou uma USB pode ter saído).
                if configurada {
                    sessao.beginConfiguration()
                    sessao.inputs.forEach(sessao.removeInput)
                    sessao.commitConfiguration()
                    configurada = false
                }
            }
            let rodando = sessao.isRunning
            // A main em ordem (FIFO), não `Task`: o último aviso tem de ser o último a chegar no `ligado`.
            DispatchQueue.main.async { aoTerminar(rodando) }
        }
    }

    /// Uma vez só: a câmera padrão como entrada, sem saída (o preview não precisa de uma) e sem microfone.
    private func configurar() -> Bool {
        if configurada { return true }
        guard let dispositivo = AVCaptureDevice.default(for: .video),
              let entrada = try? AVCaptureDeviceInput(device: dispositivo) else {
            registro.notice("espelho: não deu para abrir a câmera")
            return false
        }
        sessao.beginConfiguration()
        defer { sessao.commitConfiguration() }
        // É um espelho pequeno: a resolução média basta e gasta menos.
        if sessao.canSetSessionPreset(.medium) { sessao.sessionPreset = .medium }
        guard sessao.canAddInput(entrada) else {
            registro.notice("espelho: a sessão recusou a câmera")
            return false
        }
        sessao.addInput(entrada)
        configurada = true
        return true
    }
}
