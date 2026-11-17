import AVFoundation

/// Só a regra pura: o teste nunca liga a câmera.
@MainActor func testarEspelho() {
    conferir("espelho: permitido", Espelho.acesso(status: .authorized, temCamera: true), .permitido)
    conferir("espelho: ainda não pedido", Espelho.acesso(status: .notDetermined, temCamera: true), .naoPedido)
    conferir("espelho: negado", Espelho.acesso(status: .denied, temCamera: true), .negado)
    conferir("espelho: restrito conta como negado", Espelho.acesso(status: .restricted, temCamera: true), .negado)
    conferir("espelho: sem câmera vence a permissão", Espelho.acesso(status: .authorized, temCamera: false), .semCamera)
    conferir("espelho: sem câmera e sem pedir", Espelho.acesso(status: .notDetermined, temCamera: false), .semCamera)
}
