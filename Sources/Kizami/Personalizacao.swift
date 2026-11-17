import Foundation
import Observation

/// As abas da ilha aberta. `espelho` não tem botão no cabeçalho: abre pela aba Atalhos.
enum Aba: String, CaseIterable, Sendable {
    case inicio, hoje, timer, copiados, atalhos, kanji, espelho

    /// As que podem ir para o cabeçalho, na ordem padrão.
    static let doCabecalho: [Aba] = [.inicio, .hoje, .timer, .copiados, .atalhos, .kanji]

    var simbolo: String {
        switch self {
        case .inicio: "house.fill"
        case .hoje: "calendar"
        case .timer: "timer"
        case .copiados: "doc.on.clipboard"
        case .atalhos: "command"
        case .kanji: "waveform"
        case .espelho: "person.crop.square"
        }
    }
}

/// O que as asas da ilha fechada mostram. Uma coisa por vez: a primeira que tem o que mostrar (`Personalizacao.asa`).
enum Asa: String, CaseIterable, Sendable {
    case reuniao, atividades, timer, placar, tocando, privacidade, bandeja, nada

    /// As que a pessoa ordena, na ordem padrão. Microfone/câmera e bandeja vêm sempre depois, e nada por último.
    /// A reunião chegando vem primeiro: é a única com hora marcada.
    static let ordenaveis: [Asa] = [.reuniao, .timer, .atividades, .placar, .tocando]
}

/// O que a pessoa escolheu para a ilha: as abas e a ordem delas, as seções do Início e a vez de cada coisa nas
/// asas. Cada escolha é lida no ponto único que já decidia isso (`Cabecalho`, `secoesAtuais`, `asaAtual`),
/// em vez de `if` espalhado pelas views. Só listas de nomes nos UserDefaults.
@MainActor @Observable
final class Personalizacao {
    /// As seções do Início que dá para esconder. A lista de atividades fica sempre: é o que chegou.
    enum Secao: String, CaseIterable, Sendable { case hoje, interesse, claude, tocando, apps, bandeja }

    static let chaveAbas = "ilha.abas"
    static let chaveOcultas = "ilha.secoesOcultas"
    static let chaveAsas = "ilha.asas"

    var abas: [Aba] { didSet { defaults.set(abas.map(\.rawValue), forKey: Self.chaveAbas) } }
    var ocultas: Set<Secao> { didSet { defaults.set(ocultas.map(\.rawValue).sorted(), forKey: Self.chaveOcultas) } }
    var asas: [Asa] { didSet { defaults.set(asas.map(\.rawValue), forKey: Self.chaveAsas) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        abas = Self.abas(de: defaults.stringArray(forKey: Self.chaveAbas))
        ocultas = Set((defaults.stringArray(forKey: Self.chaveOcultas) ?? []).compactMap(Secao.init))
        asas = Self.asas(de: defaults.stringArray(forKey: Self.chaveAsas))
    }

    /// A aba em que a ilha abre: a primeira da lista.
    var abaInicial: Aba { abas.first ?? .inicio }

    func mostra(_ secao: Secao) -> Bool { !ocultas.contains(secao) }

    func alternar(_ aba: Aba) {
        abas = abas.contains(aba) ? Self.abas(de: abas.filter { $0 != aba }.map(\.rawValue))
            : Self.abas(de: (abas + [aba]).map(\.rawValue))
    }

    func alternar(_ secao: Secao) {
        if ocultas.contains(secao) { ocultas.remove(secao) } else { ocultas.insert(secao) }
    }

    /// Sobe (-1) ou desce (+1) um item numa lista. Fora da lista ou na ponta, não muda nada.
    static func mover<T: Equatable>(_ item: T, _ passo: Int, em lista: [T]) -> [T] {
        guard let i = lista.firstIndex(of: item), lista.indices.contains(i + passo) else { return lista }
        var nova = lista
        nova.swapAt(i, i + passo)
        return nova
    }

    // MARK: Regras puras

    /// As abas salvas, validadas: nomes conhecidos, sem repetidos, sem o espelho (não tem botão) e com o Início
    /// sempre (é onde as atividades aparecem). Sem nada salvo, a ordem padrão.
    static func abas(de brutos: [String]?) -> [Aba] {
        guard let brutos else { return Aba.doCabecalho }
        var vistas = Set<Aba>()
        let validas = brutos.compactMap(Aba.init).filter { Aba.doCabecalho.contains($0) && vistas.insert($0).inserted }
        return validas.contains(.inicio) ? validas : [.inicio] + validas
    }

    /// A ordem das asas salva, validada: as ordenáveis conhecidas, sem repetidos. Uma que falta (uma asa nova numa
    /// versão nova, como a reunião) entra logo depois da que vem antes dela na ordem padrão, ou no começo: no fim,
    /// a reunião ficaria atrás da música e não apareceria para quem já tinha salvo uma ordem.
    static func asas(de brutos: [String]?) -> [Asa] {
        var vistas = Set<Asa>()
        var ordem = (brutos ?? []).compactMap(Asa.init).filter { Asa.ordenaveis.contains($0) && vistas.insert($0).inserted }
        for (i, asa) in Asa.ordenaveis.enumerated() where !vistas.contains(asa) {
            let anterior = Asa.ordenaveis[..<i].last(where: ordem.contains)
            ordem.insert(asa, at: anterior.flatMap { ordem.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        }
        return ordem
    }

    /// A asa da vez. Atividade alta ou urgente (reunião, permissão do Claude) passa na frente de tudo, seja qual for
    /// a ordem: é o que não pode esperar. Depois, a primeira da ordem da pessoa que tem o que mostrar.
    static func asa(ordem: [Asa], importante: Bool, tem: (Asa) -> Bool) -> Asa {
        if importante && tem(.atividades) { return .atividades }
        return (ordem + [.privacidade, .bandeja]).first(where: tem) ?? .nada
    }
}
