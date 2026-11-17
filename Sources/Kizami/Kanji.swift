import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

// A aba do Kanji: os atalhos globais do app irmão de ditado num clique. Mesmo princípio da aba de atalhos
// (`Atalho`): a ilha recolhe, o foco volta ao app da pessoa e o Kizami manda a combinação como evento de teclado;
// o Carbon do Kanji recebe como se fosse o teclado. O texto ditado cai no app em que a pessoa estava.

/// Uma combinação pronta para mandar como evento, com a legenda escrita como o macOS escreve nos menus.
struct TeclasDoKanji: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
    let legenda: String

    /// Máscaras do Carbon (as que o Kanji grava) e as flags do CGEvent equivalentes, na ordem dos menus do macOS.
    private static let modificadores: [(carbon: Int, flag: CGEventFlags, simbolo: String)] = [
        (controlKey, .maskControl, "⌃"), (optionKey, .maskAlternate, "⌥"), (shiftKey, .maskShift, "⇧"), (cmdKey, .maskCommand, "⌘"),
    ]
    private static let mascaraValida = controlKey | optionKey | shiftKey | cmdKey

    /// nil fora do que o gravador do Kanji aceita: tecla virtual fora da faixa, bit de modificador desconhecido ou
    /// atalho sem ⌘, ⌃ ou ⌥ (só com ⇧ roubaria a digitação). O valor vem de outro app: é dado, não confiança.
    init?(keyCode: Int, carbon: Int, tecla: String) {
        let tecla = tecla.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (0..<128).contains(keyCode), carbon & ~Self.mascaraValida == 0,
              carbon & (cmdKey | controlKey | optionKey) != 0, (1...8).contains(tecla.count) else { return nil }
        let usados = Self.modificadores.filter { carbon & $0.carbon != 0 }
        self.keyCode = CGKeyCode(keyCode)
        flags = CGEventFlags(usados.map(\.flag))
        // "Espaço" fica gravado assim pelo Kanji; nome de tecla não se traduz, o símbolo serve nas duas línguas.
        legenda = usados.map(\.simbolo).joined() + (tecla == "Espaço" ? "␣" : tecla)
    }

    private struct Gravado: Decodable {
        let tecla: String
        let keyCode: Int
        let modificadores: Int
    }

    /// O JSON que o Kanji grava em `atalho.<n>`. Faltando, ilegível ou inválido: o padrão do Kanji.
    /// `exigirCtrlOpt`: a versão nova do Kanji trata um atalho gravado sem ⌃⌥ (os antigos ⇧⌘D, ⇧⌘T) como o padrão;
    /// mandar o antigo dispararia nada.
    static func decodificar(_ dados: Data?, padrao: TeclasDoKanji, exigirCtrlOpt: Bool) -> TeclasDoKanji {
        guard let dados, dados.count < 1024, let gravado = try? JSONDecoder().decode(Gravado.self, from: dados),
              !exigirCtrlOpt || gravado.modificadores & (controlKey | optionKey) == controlKey | optionKey,
              let teclas = TeclasDoKanji(keyCode: gravado.keyCode, carbon: gravado.modificadores, tecla: gravado.tecla)
        else { return padrao }
        return teclas
    }

    /// ⇧⌘ + a tecla da skill, a combinação fixa que o Kanji registra para ela.
    static func daSkill(_ tecla: String) -> TeclasDoKanji? {
        codigos[tecla].flatMap { TeclasDoKanji(keyCode: $0, carbon: cmdKey | shiftKey, tecla: tecla) }
    }

    /// Só as teclas que uma skill pode ter (`SkillDoKanji.teclas`), na posição do teclado ANSI.
    static let codigos: [String: Int] = [
        "1": kVK_ANSI_1, "2": kVK_ANSI_2, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
        "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "O": kVK_ANSI_O, "R": kVK_ANSI_R, "U": kVK_ANSI_U, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y,
    ]

    fileprivate static func padrao(_ keyCode: Int, _ tecla: String) -> TeclasDoKanji {
        TeclasDoKanji(keyCode: keyCode, carbon: controlKey | optionKey, tecla: tecla)!
    }
}

/// Um atalho global do Kanji: o que ele faz e a combinação gravada nos ajustes dele.
struct AcaoKanji: Equatable, Identifiable {
    enum Tipo: Int {
        // Os números são as chaves `atalho.<n>` do Kanji.
        case ditar = 1, abrir = 2, transcrever = 4
    }

    let tipo: Tipo
    let teclas: TeclasDoKanji
    var id: Int { tipo.rawValue }

    var nome: LocalizedStringKey {
        switch tipo {
        case .ditar: "Ditar"
        case .transcrever: "Transcrever o Mac"
        case .abrir: "Abrir"
        }
    }

    var ajuda: LocalizedStringKey {
        switch tipo {
        case .ditar: "Começa ou para o ditado no app em que você está"
        case .transcrever: "Começa ou para a transcrição do áudio que o Mac está tocando"
        case .abrir: "Abre a janela do Kanji"
        }
    }

    var simbolo: String {
        switch tipo {
        case .ditar: "mic.fill"
        case .transcrever: "waveform"
        case .abrir: "macwindow"
        }
    }

    /// As ações na ordem da aba. `nova`: o Kanji com transcrição do Mac, que mudou o padrão de abrir (⌃⌥T → ⌃⌥K)
    /// e passou a ignorar atalho sem ⌃⌥.
    static func lidas(nova: Bool, gravado: (String) -> Data?) -> [AcaoKanji] {
        let padroes: [(Tipo, TeclasDoKanji)] = [
            (.ditar, .padrao(kVK_ANSI_D, "D")),
            nova ? (.transcrever, .padrao(kVK_ANSI_M, "M")) : nil,
            (.abrir, nova ? .padrao(kVK_ANSI_K, "K") : .padrao(kVK_ANSI_T, "T")),
        ].compactMap { $0 }
        return padroes.map { tipo, padrao in
            AcaoKanji(tipo: tipo, teclas: .decodificar(gravado("atalho.\(tipo.rawValue)"), padrao: padrao, exigirCtrlOpt: nova))
        }
    }
}

/// Uma skill do Kanji, só com o que está no cabeçalho do SKILL.md. A instrução e o `contexto:` são da pessoa: não se leem.
struct SkillDoKanji: Equatable, Identifiable {
    let id: String
    let nome: String
    let cor: String
    /// nil: sem atalho válido, ou a mesma combinação de outra skill ou de uma ação (o Kanji só registra a primeira).
    let tecla: String?

    var teclas: TeclasDoKanji? { tecla.flatMap(TeclasDoKanji.daSkill) }

    /// As mesmas do Kanji (`Skill.teclas`): fora as que o macOS e quase todo app já usam com ⇧⌘.
    static let teclas = ["1", "2", "7", "8", "9"] + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init).filter { !"QZVTNSPW".contains($0) }
    /// As cores de `CorDaSkill` no Kanji, na mesma ordem: a cor de quem não escolheu sai do mesmo cálculo.
    static let cores = ["verde", "azul", "roxo", "rosa", "ciano", "amarelo"]
    static let limiteDeLeitura = 16 * 1024

    init(id: String, campos: [String: String]) {
        self.id = id
        nome = [campos["nome"], campos["name"]].compactMap { $0 }.first { !$0.isEmpty } ?? id
        cor = campos["cor"].map { $0.lowercased() }.flatMap { Self.cores.contains($0) ? $0 : nil }
            ?? Self.cores[Int(id.unicodeScalars.reduce(0) { $0 + $1.value }) % Self.cores.count]
        tecla = campos["atalho"].map { $0.uppercased() }.flatMap { Self.teclas.contains($0) ? $0 : nil }
    }

    private init(_ outra: SkillDoKanji, tecla: String?) {
        id = outra.id
        nome = outra.nome
        cor = outra.cor
        self.tecla = tecla
    }

    /// Os campos do cabeçalho entre as linhas "---", parando na que fecha: o corpo nunca é olhado.
    /// nil quando o texto acabou no meio do cabeçalho e ainda falta ler (`inteiro` false); a última linha
    /// de um pedaço pode estar cortada, então só contam as completas. Sem cabeçalho fechado: nenhum campo, como no Kanji.
    static func cabecalho(_ texto: String, inteiro: Bool) -> [String: String]? {
        let partes = texto.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let linhas = (inteiro ? partes[...] : partes.dropLast()).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let primeira = linhas.first else { return inteiro ? [:] : nil }
        guard primeira == "---" else { return [:] }
        var campos: [String: String] = [:]
        for linha in linhas.dropFirst() {
            if linha == "---" { return campos }
            let par = linha.split(separator: ":", maxSplits: 1)
            guard par.count == 2 else { continue }
            campos[par[0].trimmingCharacters(in: .whitespaces).lowercased()] = par[1].trimmingCharacters(in: .whitespaces)
        }
        return inteiro ? [:] : nil
    }

    /// Lê o SKILL.md aos pedaços e para assim que o cabeçalho fecha (ou no limite): o resto do arquivo nem entra na memória.
    static func ler(_ arquivo: URL, id: String) -> SkillDoKanji? {
        guard let leitor = try? FileHandle(forReadingFrom: arquivo) else { return nil }
        defer { try? leitor.close() }
        var lido = Data()
        while true {
            let pedaco = (try? leitor.read(upToCount: 512)) ?? Data()
            lido.append(pedaco)
            let fim = pedaco.isEmpty || lido.count >= limiteDeLeitura
            if let campos = cabecalho(String(decoding: lido, as: UTF8.self), inteiro: fim) {
                return SkillDoKanji(id: id, campos: campos)
            }
        }
    }

    /// Na ordem do Kanji (com atalho primeiro, pela tecla; depois pelo nome). Uma combinação repetida, ou igual à de
    /// uma ação, dispara outra coisa no Kanji: a skill fica sem atalho na aba.
    static func organizar(_ skills: [SkillDoKanji], acoes: [AcaoKanji]) -> [SkillDoKanji] {
        let ordenadas = skills.sorted { a, b in
            (a.tecla == nil ? 1 : 0, a.tecla ?? "", a.nome) < (b.tecla == nil ? 1 : 0, b.tecla ?? "", b.nome)
        }
        var ocupadas = acoes.map(\.teclas)
        return ordenadas.map { skill in
            guard let teclas = skill.teclas,
                  !ocupadas.contains(where: { $0.keyCode == teclas.keyCode && $0.flags == teclas.flags }) else {
                return SkillDoKanji(skill, tecla: nil)
            }
            ocupadas.append(teclas)
            return skill
        }
    }
}

/// A ponte com o Kanji: lê os atalhos e as skills dele e manda a combinação certa quando a pessoa clica.
@MainActor @Observable
final class PonteKanji {
    static let bundleID = "io.github.henriquebap.kanji"

    private(set) var instalado = false
    private(set) var rodando = false
    private(set) var acoes: [AcaoKanji] = []
    private(set) var skills: [SkillDoKanji] = []
    @ObservationIgnored private let mural: Mural

    init(mural: Mural) {
        self.mural = mural
        recarregar()
    }

    /// Relê tudo. Barato (um plist e o cabeçalho de cada SKILL.md): a aba chama ao aparecer.
    // ponytail: sem vigiar a pasta nem os ajustes do Kanji; recarregar ao abrir a aba basta enquanto a lista for curta.
    func recarregar() {
        rodando = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            (instalado, acoes, skills) = (false, [], [])
            return
        }
        instalado = true
        let ajustes = UserDefaults(suiteName: Self.bundleID)
        // A transcrição do Mac trouxe a permissão de ouvir o áudio do sistema: é o sinal de que a versão instalada a tem.
        let nova = Bundle(url: app)?.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") != nil
            || ajustes?.data(forKey: "atalho.4") != nil
        acoes = AcaoKanji.lidas(nova: nova) { ajustes?.data(forKey: $0) }
        skills = SkillDoKanji.organizar(Self.lerSkills(), acoes: acoes)
        registro.info("kanji: \(self.acoes.count) ações, \(self.skills.count) skills")
    }

    private static func lerSkills() -> [SkillDoKanji] {
        let fm = FileManager.default
        guard let suporte = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return [] }
        let pasta = suporte.appendingPathComponent("Kanji/Skills", isDirectory: true)
        let ids = (try? fm.contentsOfDirectory(atPath: pasta.path)) ?? []
        // ponytail: o Kanji também descarta skill sem instrução no corpo; aqui ela aparece, porque o corpo não se lê.
        return ids.filter { !$0.hasPrefix(".") }.prefix(64).compactMap { id in
            SkillDoKanji.ler(pasta.appendingPathComponent(id).appendingPathComponent("SKILL.md"), id: id)
        }
    }

    func executar(_ acao: AcaoKanji) { enviar(acao.teclas) }

    func executar(_ skill: SkillDoKanji) {
        guard let teclas = skill.teclas else { return }
        enviar(teclas)
    }

    /// Com o Kanji fechado, a tecla não teria quem ouvisse: o clique abre o app e avisa para clicar de novo.
    private func enviar(_ teclas: TeclasDoKanji) {
        rodando = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        guard rodando else { return abrirKanji() }
        guard Teclado.enviar(teclas.keyCode, teclas.flags, mural: mural) else { return }
        registro.info("kanji: atalho enviado")
    }

    private func abrirKanji() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
            instalado = false
            return
        }
        let configuracao = NSWorkspace.OpenConfiguration()
        configuracao.activates = false  // o foco fica no app da pessoa, onde o próximo ditado vai cair
        NSWorkspace.shared.openApplication(at: app, configuration: configuracao) { _, erro in
            if erro != nil { registro.error("kanji: não abriu") }
        }
        mural.receber(Atividade(id: "kizami-kanji", titulo: String(localized: "Abrindo o Kanji…"),
                                detalhe: String(localized: "Clique de novo quando ele abrir"), simbolo: "mic.fill",
                                cor: "azul", expira: 6))
        registro.notice("kanji: estava fechado, abrindo")
    }
}

/// Mandar uma combinação de teclas como evento, o mesmo caminho do `Atalho`.
enum Teclado {
    /// false sem a permissão de Acessibilidade: pede (o macOS mostra o aviso uma vez) e deixa na ilha como liberar.
    @MainActor static func enviar(_ tecla: CGKeyCode, _ flags: CGEventFlags, mural: Mural) -> Bool {
        guard CGPreflightPostEventAccess() else {
            CGRequestPostEventAccess()
            mural.receber(Atividade(id: "kizami-atalhos", titulo: String(localized: "Atalhos pedem Acessibilidade"),
                                    detalhe: String(localized: "Clique para liberar o Kizami"), simbolo: "keyboard",
                                    cor: "laranja", expira: 20)) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            registro.notice("teclado: sem permissão para mandar teclas")
            return false
        }
        let fonte = CGEventSource(stateID: .hidSystemState)
        for apertada in [true, false] {
            let evento = CGEvent(keyboardEventSource: fonte, virtualKey: tecla, keyDown: apertada)
            evento?.flags = flags
            evento?.post(tap: .cghidEventTap)
        }
        return true
    }
}
