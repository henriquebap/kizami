import Foundation

@MainActor func testarFones() {
    // Quem conta como fone
    conferir("classe áudio", LeituraDosFones.ehFone(classeMaior: 0x04, nome: "Caixa da sala"), true)
    conferir("mouse não", LeituraDosFones.ehFone(classeMaior: 0x05, nome: "Mouse"), false)
    conferir("AirPods pelo nome", LeituraDosFones.ehFone(classeMaior: 0x00, nome: "AirPods Pro de Ana"), true)
    conferir("Beats pelo nome", LeituraDosFones.ehFone(classeMaior: 0x1F, nome: "Beats Studio Pro"), true)
    conferir("sem nome nem classe", LeituraDosFones.ehFone(classeMaior: 0x00, nome: nil), false)

    // Porcentagens
    conferir("80%", LeituraDosFones.porcentagem("80%"), 80)
    conferir("com espaço", LeituraDosFones.porcentagem(" 7 %"), 7)
    conferir("acima de 100", LeituraDosFones.porcentagem("180%"), nil)
    conferir("negativa", LeituraDosFones.porcentagem("-5%"), nil)
    conferir("número em vez de texto", LeituraDosFones.porcentagem(80), nil)
    conferir("endereço do IOBluetooth", LeituraDosFones.endereco("98-1c-a2-e1-e8-07"), "98:1C:A2:E1:E8:07")

    // A saída do system_profiler, no formato real (nomes e endereços inventados)
    let saida = Data("""
    {"SPBluetoothDataType": [{
      "controller_properties": {"controller_address": "AA:BB:CC:DD:EE:FF", "controller_state": "attrib_on"},
      "device_connected": [
        {"Mouse do escritório": {"device_address": "D1:00:00:00:00:01", "device_minorType": "Mouse"}},
        {"AirPods Pro de Ana": {"device_address": "98:1C:A2:00:00:07", "device_batteryLevelCase": "55%",
          "device_batteryLevelLeft": "80%", "device_batteryLevelRight": "78%", "device_minorType": "Headphones"}},
        {"Beats Solo": {"device_address": "84:AC:60:00:00:02", "device_batteryLevelMain": "40%"}}
      ],
      "device_not_connected": [
        {"Fone antigo": {"device_address": "68:CA:C4:00:00:03", "device_batteryLevelLeft": "texto", "device_minorType": "Headphones"}},
        {"AirPods Pro de Ana": {"device_address": "98:1C:A2:00:00:07", "device_batteryLevelLeft": "1%"}}
      ]
    }]}
    """.utf8)
    let airpods = LeituraDosFones.bateria(saida, endereco: "98-1c-a2-00-00-07", nome: "outro nome")
    conferir("airpods pelo endereço, nos conectados", airpods, BateriaDosFones(principal: nil, esquerdo: 80, direito: 78, estojo: 55))
    conferir("detalhe dos airpods", LeituraDosFones.detalhe(airpods), "E 80% · D 78% · estojo 55%")
    let beats = LeituraDosFones.bateria(saida, endereco: nil, nome: "Beats Solo")
    conferir("beats pelo nome, bateria principal", beats, BateriaDosFones(principal: 40))
    conferir("detalhe da principal", LeituraDosFones.detalhe(beats), "40%")
    let antigo = LeituraDosFones.bateria(saida, endereco: "68:ca:c4:00:00:03", nome: nil)
    conferir("nos não conectados, bateria ilegível", antigo, BateriaDosFones())
    conferir("sem bateria é só conectado", LeituraDosFones.detalhe(antigo), "Conectado")
    conferir("aparelho que não está na lista", LeituraDosFones.bateria(saida, endereco: "00:00:00:00:00:00", nome: nil), nil)
    conferir("sem leitura é só conectado", LeituraDosFones.detalhe(nil), "Conectado")
    conferir("saída que não é JSON", LeituraDosFones.bateria(Data("erro".utf8), endereco: nil, nome: "x"), nil)
    conferir("JSON de outro formato", LeituraDosFones.bateria(Data(#"{"SPBluetoothDataType": {}}"#.utf8), endereco: nil, nome: "x"), nil)
}
