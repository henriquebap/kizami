import CoreAudio
import Foundation
import Observation

/// O volume da saída padrão, para a asa mostrar o nível quando a pessoa muda o volume.
/// Só lê: nunca muda volume, mudo nem dispositivo. O indicador do sistema continua aparecendo (ver ROADMAP):
/// escondê-lo pediria interceptar as teclas de mídia.
@MainActor @Observable
final class Volume {
    /// Quanto tempo a asa mostra o nível depois de uma mudança.
    nonisolated static let mostrarPor: TimeInterval = 1.5

    /// De 0 a 1; nil numa saída sem controle de volume (HDMI, por exemplo).
    private(set) var nivel: Double?
    private(set) var mudo = false
    /// A última mudança feita pela pessoa. A leitura ao abrir e a troca de dispositivo não contam.
    private(set) var mudouEm: Date?
    /// A asa mostra o nível agora: liga na mudança e desliga `mostrarPor` depois, por uma Task agendada, sem relógio
    /// redesenhando a ilha (a asa fechada não pode ter nada por segundo; ver Energy no ARCHITECTURE).
    private(set) var naAsa = false
    @ObservationIgnored private var esconder: Task<Void, Never>?

    /// O dispositivo ouvido agora, os endereços em que o ouvinte entrou e o próprio ouvinte: para tirar o
    /// mesmo bloco dos mesmos endereços quando a saída padrão muda.
    @ObservationIgnored private var ouvido: (dispositivo: AudioObjectID, enderecos: [AudioObjectPropertyAddress],
                                             ouvinte: AudioObjectPropertyListenerBlock)?
    @ObservationIgnored private var ouvindoSistema = false

    /// Se a asa mostra o nível em `agora`.
    nonisolated static func visivel(mudouEm: Date?, agora: Date) -> Bool {
        guard let mudouEm else { return false }
        let passou = agora.timeIntervalSince(mudouEm)
        return passou >= 0 && passou < mostrarPor
    }

    // ponytail: ouvintes e leituras na thread principal; ler o volume é uma chamada só, ao contrário da lista de
    // processos do `TocandoAgora`. Passar para uma fila serial se a troca de dispositivo travar a ilha.
    func iniciar() {
        guard !ouvindoSistema else { return }
        var endereco = Self.endereco(kAudioHardwarePropertyDefaultOutputDevice, escopo: kAudioObjectPropertyScopeGlobal)
        let ouvinte: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.ouvirSaidaPadrao() }
        }
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &endereco, .main, ouvinte)
        guard status == noErr else {
            registro.error("volume: sem ouvinte da saída padrão (\(status, privacy: .public))")
            return
        }
        ouvindoSistema = true
        ouvirSaidaPadrao()
    }

    /// Troca os ouvintes para a saída padrão de agora e lê o volume dela sem contar como mudança da pessoa.
    private func ouvirSaidaPadrao() {
        if let ouvido {
            for var endereco in ouvido.enderecos {
                AudioObjectRemovePropertyListenerBlock(ouvido.dispositivo, &endereco, .main, ouvido.ouvinte)
            }
            self.ouvido = nil
        }
        let dispositivo = Self.saidaPadrao()
        let ouvinte: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.ler(dispositivo, pelaPessoa: true) }
        }
        let enderecos = Self.enderecos(dispositivo).filter { endereco in
            var endereco = endereco
            return AudioObjectAddPropertyListenerBlock(dispositivo, &endereco, .main, ouvinte) == noErr
        }
        ouvido = (dispositivo, enderecos, ouvinte)
        registro.info("volume: saída padrão com \(enderecos.count, privacy: .public) propriedade(s) ouvida(s)")
        ler(dispositivo, pelaPessoa: false)
    }

    private func ler(_ dispositivo: AudioObjectID, pelaPessoa: Bool) {
        guard dispositivo == ouvido?.dispositivo else { return }  // aviso atrasado do dispositivo anterior
        let nivel = Self.lerNivel(dispositivo)
        let mudo = Self.lerNumero(dispositivo, kAudioDevicePropertyMute, elemento: kAudioObjectPropertyElementMain)
            .map { $0 != 0 } ?? false
        guard nivel != self.nivel || mudo != self.mudo else { return }
        if nivel != self.nivel { self.nivel = nivel }
        if mudo != self.mudo { self.mudo = mudo }
        if pelaPessoa { mostrar() }
    }

    private func mostrar() {
        mudouEm = .now
        if !naAsa { naAsa = true }
        esconder?.cancel()
        esconder = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.mostrarPor))
            guard !Task.isCancelled else { return }
            self?.naAsa = false
        }
    }

    // MARK: Core Audio

    nonisolated private static func saidaPadrao() -> AudioObjectID {
        var endereco = endereco(kAudioHardwarePropertyDefaultOutputDevice, escopo: kAudioObjectPropertyScopeGlobal)
        var dispositivo = AudioObjectID(kAudioObjectUnknown)
        var tamanho = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &endereco, 0, nil, &tamanho, &dispositivo)
        return status == noErr ? dispositivo : AudioObjectID(kAudioObjectUnknown)
    }

    /// O volume geral; sem ele (muitas placas só têm por canal), a média dos canais 1 e 2.
    nonisolated private static func lerNivel(_ dispositivo: AudioObjectID) -> Double? {
        if let geral = lerNumero(dispositivo, kAudioDevicePropertyVolumeScalar, elemento: kAudioObjectPropertyElementMain) {
            return geral
        }
        let canais = [1, 2].compactMap { lerNumero(dispositivo, kAudioDevicePropertyVolumeScalar, elemento: $0) }
        return canais.isEmpty ? nil : canais.reduce(0, +) / Double(canais.count)
    }

    /// Volume do geral e dos canais 1 e 2, e o mudo: só os que o dispositivo tem.
    nonisolated private static func enderecos(_ dispositivo: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let elementos = [kAudioObjectPropertyElementMain, 1, 2]
        let todos = elementos.map { endereco(kAudioDevicePropertyVolumeScalar, elemento: $0) }
            + [endereco(kAudioDevicePropertyMute)]
        return todos.filter { endereco in
            var endereco = endereco
            return AudioObjectHasProperty(dispositivo, &endereco)
        }
    }

    /// Volume (Float32) ou mudo (UInt32) como número; nil se o dispositivo não tem a propriedade.
    nonisolated private static func lerNumero(_ dispositivo: AudioObjectID, _ seletor: AudioObjectPropertySelector,
                                             elemento: AudioObjectPropertyElement) -> Double? {
        var endereco = endereco(seletor, elemento: elemento)
        guard dispositivo != AudioObjectID(kAudioObjectUnknown), AudioObjectHasProperty(dispositivo, &endereco) else { return nil }
        var tamanho = UInt32(4)
        if seletor == kAudioDevicePropertyMute {
            var valor: UInt32 = 0
            return AudioObjectGetPropertyData(dispositivo, &endereco, 0, nil, &tamanho, &valor) == noErr ? Double(valor) : nil
        }
        var valor: Float32 = 0
        return AudioObjectGetPropertyData(dispositivo, &endereco, 0, nil, &tamanho, &valor) == noErr ? Double(valor) : nil
    }

    nonisolated private static func endereco(_ seletor: AudioObjectPropertySelector,
                                             escopo: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
                                             elemento: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: seletor, mScope: escopo, mElement: elemento)
    }
}
