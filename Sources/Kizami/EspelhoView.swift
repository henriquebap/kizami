import AppKit
import AVFoundation
import SwiftUI

/// A aba do espelho na ilha aberta: a câmera, espelhada como um espelho, para se ver antes de uma chamada.
/// Liga ao aparecer e desliga ao sumir; a ilha também chama `desligar()` ao fechar e ao trocar de aba.
struct AbaEspelho: View {
    let estado: EstadoIlha
    let espelho: Espelho

    /// A ilha aberta tem 340 pt de largura e 10 de margem: 320 × 190 fica perto do 16:9 de uma chamada.
    static let altura: CGFloat = 190

    init(estado: EstadoIlha, espelho: Espelho) {
        self.estado = estado
        self.espelho = espelho
    }

    var body: some View {
        conteudo
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
            .frame(height: Self.altura)
    }

    @ViewBuilder private var conteudo: some View {
        switch espelho.acesso {
        case .permitido:
            PreviewDaCamera(sessao: espelho.sessao, ligado: espelho.ligado)
                .overlay { if !espelho.ligado { ProgressView().controlSize(.small) } }
        case .naoPedido:
            aviso("video", Text("Pedindo acesso à câmera…"))
        case .negado:
            aviso("video.slash", Text("O Kizami não tem acesso à câmera")) {
                Button("Liberar nos Ajustes do Sistema") {
                    // A ilha recolhe para os Ajustes do Sistema não abrirem por baixo dela.
                    estado.recolher = true
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        case .semCamera:
            aviso("video.slash", Text("Nenhuma câmera encontrada"))
        }
    }

    private func aviso(_ simbolo: String, _ texto: Text,
                       @ViewBuilder acao: () -> some View = { EmptyView() }) -> some View {
        VStack(spacing: 8) {
            Image(systemName: simbolo).font(.system(size: 22, weight: .medium)).foregroundStyle(.secondary)
            texto.font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            acao()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .vidro(raio: 12)
    }
}

/// Hospeda a `AVCaptureVideoPreviewLayer`: a imagem vai da câmera direto para a tela, sem passar pelo app.
private struct PreviewDaCamera: NSViewRepresentable {
    let sessao: AVCaptureSession
    /// Só para o `updateNSView` rodar quando a câmera liga: a conexão da layer nasce com a entrada da sessão.
    let ligado: Bool

    func makeNSView(context: Context) -> NSView {
        let camada = AVCaptureVideoPreviewLayer(session: sessao)
        camada.videoGravity = .resizeAspectFill
        // Os cantos na própria layer: o clipShape do SwiftUI não recorta uma layer hospedada numa NSView.
        camada.cornerRadius = 12
        camada.masksToBounds = true
        let vista = NSView()
        vista.layer = camada  // antes do wantsLayer: a NSView hospeda a layer em vez de criar a sua
        vista.wantsLayer = true
        espelhar(camada)
        return vista
    }

    func updateNSView(_ vista: NSView, context: Context) {
        if let camada = vista.layer as? AVCaptureVideoPreviewLayer { espelhar(camada) }
    }

    /// Como num espelho: a pessoa levanta a mão direita e a imagem levanta a da direita.
    private func espelhar(_ camada: AVCaptureVideoPreviewLayer) {
        guard let conexao = camada.connection, conexao.isVideoMirroringSupported else { return }
        conexao.automaticallyAdjustsVideoMirroring = false
        conexao.isVideoMirrored = true
    }
}
