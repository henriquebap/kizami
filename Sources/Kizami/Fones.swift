import Foundation
import IOBluetooth
import Observation

/// O aviso de fone conectado (AirPods e outros fones Bluetooth), com a bateria, se a pessoa ligar nos Ajustes.
/// Só escuta conexões e lê o `system_profiler`: nunca conecta, desconecta nem mexe na saída de áudio.
@MainActor @Observable
final class Fones {
    static let chave = "fones.ligado"
    /// Ao registrar, o IOBluetooth avisa também dos aparelhos que já estavam conectados: o que chega nesta janela
    /// não é uma conexão nova, e avisar dela a cada abertura do app seria barulho.
    private static let silencioInicial: TimeInterval = 2
    /// Logo depois de conectar, os AirPods ainda não disseram a bateria ao Mac.
    // ponytail: espera fixa. Fone que demora mais que isso sai como "Conectado"; ler de novo se incomodar.
    private static let esperaPelaBateria: Duration = .seconds(3)

    /// Desligado por padrão: só liga nos Ajustes. Ligar é o que faz o macOS pedir o acesso ao Bluetooth.
    var ligado: Bool {
        didSet {
            guard ligado != oldValue else { return }
            UserDefaults.standard.set(ligado, forKey: Self.chave)
            ligado ? comecar() : parar()
        }
    }

    @ObservationIgnored private let mural: Mural
    @ObservationIgnored private var ouvinte: OuvinteDeConexao?
    @ObservationIgnored private var inscricao: IOBluetoothUserNotification?
    @ObservationIgnored private var registradoEm = Date.distantPast
    @ObservationIgnored private var leitura: Task<Void, Never>?

    init(mural: Mural) {
        self.mural = mural
        self.ligado = UserDefaults.standard.bool(forKey: Self.chave)
    }

    func iniciar() {
        if ligado { comecar() }
    }

    private func comecar() {
        guard inscricao == nil else { return }
        let ouvinte = OuvinteDeConexao { [weak self] nome, endereco, classe in self?.conectou(nome: nome, endereco: endereco, classe: classe) }
        registradoEm = .now
        // Entregue no run loop principal, onde foi registrado.
        inscricao = IOBluetoothDevice.register(forConnectNotifications: ouvinte, selector: #selector(OuvinteDeConexao.conectou(_:dispositivo:)))
        self.ouvinte = ouvinte
        if inscricao == nil { registro.notice("fones: registro de conexões falhou") }
    }

    private func parar() {
        inscricao?.unregister()
        inscricao = nil
        ouvinte = nil
        leitura?.cancel()
        leitura = nil
        mural.remover(id: "fones")
    }

    private func conectou(nome: String?, endereco: String?, classe: UInt32) {
        guard ligado, Date.now.timeIntervalSince(registradoEm) > Self.silencioInicial,
              LeituraDosFones.ehFone(classeMaior: classe, nome: nome) else { return }
        leitura?.cancel()
        leitura = Task { [weak self] in
            try? await Task.sleep(for: Fones.esperaPelaBateria)
            guard !Task.isCancelled else { return }
            let dados = await Fones.perfil()
            guard let self, self.ligado, !Task.isCancelled else { return }
            let bateria = dados.flatMap { LeituraDosFones.bateria($0, endereco: endereco, nome: nome) }
            // O nome do aparelho é conteúdo: no log, só se achou a bateria.
            if bateria == nil { registro.info("fones: conectado, bateria desconhecida") } else { registro.info("fones: conectado, bateria lida") }
            let titulo = Atividade.limpo(nome ?? "", ate: 60)
            self.mural.receber(Atividade(id: "fones", titulo: titulo.isEmpty ? String(localized: "Fones") : titulo,
                                         detalhe: LeituraDosFones.detalhe(bateria), simbolo: Fones.simbolo(nome),
                                         cor: "azul", expira: 8, prioridade: "normal"))
        }
    }

    private static func simbolo(_ nome: String?) -> String {
        let nome = nome?.lowercased() ?? ""
        guard nome.contains("airpods") else { return "headphones" }
        return nome.contains("max") ? "airpodsmax" : "airpodspro"
    }
}

/// O alvo Objective-C que o IOBluetooth chama. Só tira do aparelho o nome, o endereço e a classe, e passa adiante.
@MainActor
private final class OuvinteDeConexao: NSObject {
    private let aoConectar: (String?, String?, UInt32) -> Void

    init(aoConectar: @escaping (String?, String?, UInt32) -> Void) {
        self.aoConectar = aoConectar
    }

    /// O IOBluetooth chama no run loop principal, onde a inscrição foi feita. O aparelho não é `Sendable`:
    /// sai dele só texto e número antes de entrar no ator principal.
    @objc nonisolated func conectou(_ notificacao: IOBluetoothUserNotification, dispositivo: IOBluetoothDevice) {
        let (nome, endereco, classe) = (dispositivo.name, dispositivo.addressString, dispositivo.deviceClassMajor)
        MainActor.assumeIsolated {
            aoConectar(nome, endereco, classe)
        }
    }
}

// MARK: O processo

extension Fones {
    private nonisolated static let programa = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    private nonisolated static let limite: TimeInterval = 10
    /// Uma dúzia de aparelhos dá uns 4 KB; muito além disso não é a nossa leitura.
    private nonisolated static let tamanhoMaximo = 1_000_000

    /// Roda o `system_profiler` com argumentos fixos, fora da thread principal, com `limite` e `tamanhoMaximo`.
    nonisolated static func perfil() async -> Data? {
        await withCheckedContinuation { continuacao in
            DispatchQueue.global(qos: .utility).async {
                continuacao.resume(returning: rodar())
            }
        }
    }

    private nonisolated static func rodar() -> Data? {
        let processo = Process()
        processo.executableURL = programa
        processo.arguments = ["-json", "SPBluetoothDataType"]
        let saida = Pipe()
        processo.standardOutput = saida
        processo.standardError = FileHandle.nullDevice
        processo.standardInput = FileHandle.nullDevice
        do {
            try processo.run()
        } catch {
            return nil
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + limite) {
            if processo.isRunning { processo.terminate() }
        }
        // Lê enquanto roda: esperar o fim antes de ler trava o processo quando a saída passa do buffer do pipe.
        let dados = (try? saida.fileHandleForReading.read(upToCount: tamanhoMaximo + 1)) ?? Data()
        if dados.count > tamanhoMaximo, processo.isRunning { processo.terminate() }
        processo.waitUntilExit()
        guard processo.terminationStatus == 0, processo.terminationReason == .exit, dados.count <= tamanhoMaximo else { return nil }
        return dados
    }
}
