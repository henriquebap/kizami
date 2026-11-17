import Foundation

/// A bateria de um fone, como o `system_profiler` mostra. Cada parte é 0 a 100, ou nil quando o fone não diz:
/// AirPods dão esquerdo, direito e estojo; fones de uma bateria só (Beats, headsets) dão a principal.
struct BateriaDosFones: Equatable, Sendable {
    var principal: Int?
    var esquerdo: Int?
    var direito: Int?
    var estojo: Int?
}

/// As regras puras dos fones: qual aparelho conta como fone e a leitura do `system_profiler`.
/// Fora do `Fones.swift` para o teste não precisar do IOBluetooth.
enum LeituraDosFones {
    /// A classe maior "áudio/vídeo" do Bluetooth (kBluetoothDeviceClassMajorAudio, 0x04).
    static let classeDeAudio: UInt32 = 0x04

    /// Fone de ouvido, caixa de som, headset. AirPods e Beats pelo nome também: há modelos que se anunciam com outra
    /// classe, ou sem ela, nos primeiros instantes da conexão.
    static func ehFone(classeMaior: UInt32, nome: String?) -> Bool {
        if classeMaior == classeDeAudio { return true }
        let nome = nome?.lowercased() ?? ""
        return nome.contains("airpods") || nome.contains("beats")
    }

    /// O IOBluetooth escreve "98-1c-a2-e1-e8-07"; o `system_profiler`, "98:1C:A2:E1:E8:07".
    static func endereco(_ texto: String) -> String {
        texto.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    /// "80%" → 80. Fora de 0...100 ou ilegível, nil.
    static func porcentagem(_ valor: Any?) -> Int? {
        guard let texto = valor as? String else { return nil }
        let numero = texto.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        guard let n = Int(numero.trimmingCharacters(in: .whitespaces)), (0...100).contains(n) else { return nil }
        return n
    }

    /// A bateria do aparelho na saída de `system_profiler -json SPBluetoothDataType`, pelo endereço e, sem ele, pelo nome.
    /// O formato (conferido em 17/11/2026): `{"SPBluetoothDataType": [{"device_connected": [{"<nome>": {...}}],
    /// "device_not_connected": [...]}]}`. Procura nos conectados antes: logo depois de conectar, o aparelho às vezes
    /// ainda aparece na outra lista. nil se a saída não é essa ou o aparelho não está nela.
    static func bateria(_ dados: Data, endereco: String?, nome: String?) -> BateriaDosFones? {
        guard let raiz = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
              let controladores = raiz["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        let alvo = endereco.map(Self.endereco)
        for lista in ["device_connected", "device_not_connected"] {
            // Cada item é um dicionário de uma chave só: o nome do aparelho → as propriedades dele.
            let aparelhos = controladores.flatMap { ($0[lista] as? [[String: Any]]) ?? [] }.flatMap { $0 }
            let achado = aparelhos.first { chave, valor in
                guard let propriedades = valor as? [String: Any] else { return false }
                if let alvo, let dele = propriedades["device_address"] as? String { return Self.endereco(dele) == alvo }
                return nome != nil && chave == nome
            }
            guard let propriedades = achado?.value as? [String: Any] else { continue }
            return BateriaDosFones(principal: porcentagem(propriedades["device_batteryLevelMain"]),
                                   esquerdo: porcentagem(propriedades["device_batteryLevelLeft"]),
                                   direito: porcentagem(propriedades["device_batteryLevelRight"]),
                                   estojo: porcentagem(propriedades["device_batteryLevelCase"]))
        }
        return nil
    }

    /// "E 80% · D 78% · estojo 55%", só com as partes que o fone disse; sem nenhuma, "Conectado".
    static func detalhe(_ bateria: BateriaDosFones?) -> String {
        guard let bateria else { return String(localized: "Conectado") }
        let partes = [
            bateria.principal.map { "\($0)%" },
            bateria.esquerdo.map { String(localized: "E \("\($0)%")") },
            bateria.direito.map { String(localized: "D \("\($0)%")") },
            bateria.estojo.map { String(localized: "estojo \("\($0)%")") },
        ].compactMap { $0 }
        return partes.isEmpty ? String(localized: "Conectado") : partes.joined(separator: " · ")
    }
}
