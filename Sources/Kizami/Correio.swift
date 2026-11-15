import Foundation

/// O que a linha de comando pediu.
enum Pedido: Equatable {
    case enviar(Atividade)
    case remover(String)
    case limpar
}

/// Linha de comando: o próprio binário do app, chamado com uma ação, avisa o Kizami que está rodando e sai.
///     Kizami.app/Contents/MacOS/Kizami enviar --titulo "Build pronto" --simbolo hammer --cor verde
enum Comando {
    private static let opcoes: [String: Set<String>] = [
        "enviar": ["titulo", "detalhe", "simbolo", "cor", "id", "expira"],
        "remover": ["id"],
        "limpar": [],
    ]

    static let ajuda = """
        uso: Kizami enviar --titulo TEXTO [--detalhe TEXTO] [--simbolo SF_SYMBOL] [--cor COR] [--id ID] [--expira SEGUNDOS]
             Kizami remover --id ID
             Kizami limpar
        cores: \(Atividade.cores.sorted().joined(separator: ", "))
        --expira 0 deixa a atividade na ilha até "remover"; sem --expira, some em \(Int(Atividade.expiraPadrao)) s.
        """

    /// nil quando falta algo ou sobra uma opção desconhecida: um erro de digitação não pode passar calado.
    static func ler(_ argumentos: [String]) -> Pedido? {
        guard let acao = argumentos.first, let aceitas = opcoes[acao] else { return nil }
        var valores: [String: String] = [:]
        var resto = argumentos.dropFirst()
        while let chave = resto.popFirst() {
            let nome = String(chave.dropFirst(2))
            guard chave.hasPrefix("--"), aceitas.contains(nome), let valor = resto.popFirst() else { return nil }
            valores[nome] = valor
        }
        switch acao {
        case "enviar":
            guard let titulo = valores["titulo"] else { return nil }
            var expira: Double?
            if let texto = valores["expira"] {
                guard let numero = Double(texto), numero.isFinite else { return nil }
                expira = numero
            }
            return .enviar(Atividade(id: valores["id"] ?? UUID().uuidString, titulo: titulo, detalhe: valores["detalhe"],
                                     simbolo: valores["simbolo"], cor: valores["cor"], expira: expira))
        case "remover":
            return valores["id"].map(Pedido.remover)
        default:
            return .limpar
        }
    }

    /// Código de saída do processo.
    static func executar(_ argumentos: [String]) -> Int32 {
        guard let pedido = ler(argumentos) else {
            FileHandle.standardError.write(Data((ajuda + "\n").utf8))
            return 2
        }
        Correio.postar(pedido)
        return 0
    }
}

/// Entre processos pelo DistributedNotificationCenter: não precisa de servidor, porta nem permissão.
/// O conteúdo vai em `object` (texto), que continua chegando mesmo quando quem envia está em sandbox.
enum Correio {
    private static let prefixo = "io.github.henriquebap.kizami."
    static let enviar = Notification.Name(prefixo + "enviar")
    static let remover = Notification.Name(prefixo + "remover")
    static let limpar = Notification.Name(prefixo + "limpar")

    static func postar(_ pedido: Pedido) {
        let (nome, objeto): (Notification.Name, String?) = switch pedido {
        case .enviar(let atividade): (enviar, (try? JSONEncoder().encode(atividade)).flatMap { String(data: $0, encoding: .utf8) })
        case .remover(let id): (remover, id)
        case .limpar: (limpar, nil)
        }
        DistributedNotificationCenter.default().postNotificationName(nome, object: objeto, userInfo: nil, deliverImmediately: true)
    }

    @MainActor static func ouvir(_ mural: Mural) {
        let centro = DistributedNotificationCenter.default()
        centro.addObserver(forName: enviar, object: nil, queue: .main) { aviso in
            // 4 KB cabem com folga uma atividade inteira; mais que isso nem é decodificado.
            let dados = (aviso.object as? String).flatMap { $0.utf8.count <= 4096 ? Data($0.utf8) : nil }
            MainActor.assumeIsolated {
                guard let dados, let atividade = try? JSONDecoder().decode(Atividade.self, from: dados) else {
                    registro.notice("mensagem descartada: JSON inválido")
                    return
                }
                mural.receber(atividade)
            }
        }
        centro.addObserver(forName: remover, object: nil, queue: .main) { aviso in
            let id = aviso.object as? String
            MainActor.assumeIsolated { if let id { mural.remover(id: id) } }
        }
        centro.addObserver(forName: limpar, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { mural.limpar() }
        }
    }
}
