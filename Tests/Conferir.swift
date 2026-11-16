import Foundation

// O conferir fica num arquivo próprio: o teste de um módulo novo roda com um main de rascunho, sem o KizamiTeste.
@MainActor var falhas = 0

@MainActor func conferir<T: Equatable>(_ nome: String, _ obtido: T, _ esperado: T) {
    let ok = obtido == esperado
    print(ok ? "ok   " : "FALHA", nome, ok ? "" : "\n  obtido:   \(obtido)\n  esperado: \(esperado)")
    if !ok { falhas += 1 }
}
