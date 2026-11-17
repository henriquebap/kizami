import AppKit
import Observation

/// Um download em andamento, como a pasta mostra. O nome vem do site: é dado, limpo antes de ir para a ilha.
struct Parcial: Equatable, Sendable {
    /// O nome do parcial na pasta ("relatorio.pdf.crdownload").
    var nome: String
    var bytes: Int64
    /// Só o Safari diz o total (no Info.plist do pacote); Chrome e Firefox não deixam na pasta.
    var total: Int64?
}

/// O que mudou entre duas leituras da pasta, pelo nome do parcial.
struct MudancasDeDownload: Equatable, Sendable {
    var novos: [String] = []
    var andamento: [String] = []
    var concluidos: [String] = []
    var cancelados: [String] = []
}

/// Os downloads em andamento em `~/Downloads`, se a pessoa ligar nos Ajustes.
/// Só lê nomes, tamanhos e o Info.plist do Safari: nunca move, apaga ou abre nada sem o clique da pessoa.
@MainActor @Observable
final class Downloads {
    static let chave = "downloads.ligado"
    /// Parcial sem escrita há mais que isso está pausado ou abandonado (o Chrome deixa `.crdownload` quando cai):
    /// não é "baixando", e sem este corte ficaria na ilha para sempre.
    nonisolated static let parado: TimeInterval = 300

    enum Acesso: Equatable, Sendable { case naoPedido, liberado, negado }

    var ligado: Bool {
        didSet {
            guard ligado != oldValue else { return }
            UserDefaults.standard.set(ligado, forKey: Self.chave)
            ligado ? comecar() : parar()
        }
    }
    private(set) var acesso = Acesso.naoPedido

    @ObservationIgnored private let mural: Mural
    @ObservationIgnored private let pasta: URL
    /// Os parciais da leitura anterior: a base para decidir quem acabou.
    @ObservationIgnored private var anteriores: Set<String> = []
    /// O detalhe já mostrado por id: reenviar só quando muda, para não reordenar a ilha a cada 2 s à toa.
    @ObservationIgnored private var mostrados: [String: String] = [:]
    @ObservationIgnored private var vigia: DispatchSourceFileSystemObject?
    @ObservationIgnored private var ciclo: Task<Void, Never>?
    /// Descompactar um zip na pasta dá um evento por arquivo: espera a rajada passar e lê uma vez.
    @ObservationIgnored private var adiada: Task<Void, Never>?

    init(mural: Mural, pasta: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.mural = mural
        self.pasta = pasta
        self.ligado = UserDefaults.standard.bool(forKey: Self.chave)
    }

    func iniciar() {
        if ligado { comecar() }
    }

    // MARK: Regras puras

    nonisolated static let sufixos = [".crdownload", ".download", ".part"]  // Chrome/Edge/Brave, Safari, Firefox

    /// O nome que o arquivo terá ao terminar, ou nil se não é um parcial.
    nonisolated static func nomeFinal(_ nome: String) -> String? {
        guard let sufixo = sufixos.first(where: { nome.lowercased().hasSuffix($0) }) else { return nil }
        let final = String(nome.dropLast(sufixo.count))
        return final.isEmpty ? nil : final
    }

    /// "nome · 62%" com o total, "nome · 45 MB" sem ele. O nome é cortado antes, para o fim nunca sumir.
    nonisolated static func detalhe(nome: String, bytes: Int64, total: Int64?) -> String {
        let limpo = Atividade.limpo(nome, ate: 90)
        guard let total, total > 0 else {
            return "\(limpo) · \(ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file))"
        }
        return "\(limpo) · \(min(max(bytes * 100 / total, 0), 100))%"
    }

    /// Bytes baixados e total do Info.plist de um pacote `.download` do Safari. Total desconhecido vem como -1.
    nonisolated static func progressoDoSafari(_ info: [String: Any]) -> (bytes: Int64, total: Int64?)? {
        guard let bytes = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value, bytes >= 0 else { return nil }
        let total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
        return (bytes, total.flatMap { $0 > 0 ? $0 : nil })
    }

    /// Entre duas leituras: acabou quem sumiu deixando o arquivo final; cancelou quem sumiu sem ele.
    /// `nomes` é tudo o que está na pasta. O parcial ainda presente (parado) nunca conta como concluído:
    /// o Firefox cria o arquivo final vazio junto do `.part`, desde o começo.
    nonisolated static func decidir(antes: Set<String>, parciais: Set<String>, nomes: Set<String>) -> MudancasDeDownload {
        let sumidos = antes.subtracting(parciais)
        let concluidos = sumidos.filter { parcial in
            !nomes.contains(parcial) && nomeFinal(parcial).map(nomes.contains) == true
        }
        return MudancasDeDownload(novos: parciais.subtracting(antes).sorted(),
                                  andamento: parciais.intersection(antes).sorted(),
                                  concluidos: concluidos.sorted(),
                                  cancelados: sumidos.subtracting(concluidos).sorted())
    }

    /// Id estável pelo nome final: o "concluído" substitui o "baixando" no mesmo lugar.
    /// FNV-1a, e não `hashValue`, que muda a cada execução.
    nonisolated static func id(_ nomeFinal: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in nomeFinal.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return "download-" + String(hash, radix: 16)
    }

    // MARK: Leitura da pasta

    /// Os nomes da pasta e os parciais ativos. nil: sem acesso (negado em Arquivos e Pastas, ou a pasta não existe).
    /// Bloqueia enquanto o macOS pergunta sobre a pasta: chamar fora da thread principal.
    nonisolated static func ler(_ pasta: URL, agora: Date = .now) -> (nomes: Set<String>, parciais: [Parcial])? {
        let fm = FileManager.default
        guard let nomes = try? fm.contentsOfDirectory(atPath: pasta.path) else { return nil }
        // `.part` só com o arquivo final vazio ao lado, como o Firefox faz: arquivo dividido e rsync também usam `.part`.
        let parciais = nomes.filter { nome in
            guard let final = nomeFinal(nome) else { return false }
            return !nome.lowercased().hasSuffix(".part") || nomes.contains(final)
        }.compactMap { nome -> Parcial? in
            let url = pasta.appendingPathComponent(nome)
            var ehPasta: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &ehPasta) else { return nil }
            let lido: (bytes: Int64, total: Int64?, modificado: Date)?
            if ehPasta.boolValue {
                // Só o pacote do Safari é pasta; um ".download" que é arquivo não é dele e fica de fora.
                guard nome.lowercased().hasSuffix(".download") else { return nil }
                lido = lerPacote(url)
            } else if nome.lowercased().hasSuffix(".download") {
                return nil
            } else {
                lido = atributos(url).map { ($0.bytes, nil, $0.modificado) }
            }
            guard let lido, agora.timeIntervalSince(lido.modificado) < parado else { return nil }
            return Parcial(nome: nome, bytes: lido.bytes, total: lido.total)
        }
        return (Set(nomes), parciais)
    }

    nonisolated private static func atributos(_ url: URL) -> (bytes: Int64, modificado: Date)? {
        guard let valores = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let modificado = valores.contentModificationDate else { return nil }
        return (Int64(valores.fileSize ?? 0), modificado)
    }

    /// O pacote do Safari: o arquivo parcial e o Info.plist dentro. Sem progresso no plist, a soma do que já está lá.
    nonisolated private static func lerPacote(_ url: URL) -> (bytes: Int64, total: Int64?, modificado: Date)? {
        guard let itens = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return nil }
        let lidos = itens.compactMap(atributos)
        guard let modificado = lidos.map(\.modificado).max() else { return nil }
        if let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) as? [String: Any],
           let progresso = progressoDoSafari(info) {
            return (progresso.bytes, progresso.total, modificado)
        }
        let soma = zip(itens, lidos).filter { $0.0.lastPathComponent != "Info.plist" }.reduce(Int64(0)) { $0 + $1.1.bytes }
        return (soma, nil, modificado)
    }

    // MARK: Ciclo

    private func comecar() {
        verificar()
    }

    private func parar() {
        ciclo?.cancel()
        ciclo = nil
        vigia?.cancel()
        vigia = nil
        for parcial in anteriores { if let final = Self.nomeFinal(parcial) { mural.remover(id: Self.id(final)) } }
        anteriores = []
        mostrados = [:]
    }

    /// Lê agora e, enquanto houver parcial, de novo a cada 2 s: o tamanho de um arquivo crescendo não acorda o vigia
    /// da pasta, só entrar, sair ou renomear. Sem parcial, para e espera o vigia.
    private func verificar() {
        ciclo?.cancel()
        ciclo = Task { [weak self] in
            while !Task.isCancelled {
                guard let pasta = self?.pasta else { return }
                let leitura = await Task.detached { Downloads.ler(pasta) }.value
                guard let self, !Task.isCancelled, self.ligado else { return }
                guard self.aplicar(leitura) else { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Devolve se ainda há parcial (continua conferindo).
    private func aplicar(_ leitura: (nomes: Set<String>, parciais: [Parcial])?) -> Bool {
        guard let leitura else {
            if acesso != .negado {
                acesso = .negado
                registro.notice("downloads: sem acesso à pasta")
            }
            parar()
            return false
        }
        if acesso != .liberado { acesso = .liberado }
        vigiar()
        let atuais = Set(leitura.parciais.map(\.nome))
        let mudancas = Self.decidir(antes: anteriores, parciais: atuais, nomes: leitura.nomes)
        anteriores = atuais

        for parcial in mudancas.cancelados {
            guard let final = Self.nomeFinal(parcial) else { continue }
            mural.remover(id: Self.id(final))
            mostrados[Self.id(final)] = nil
        }
        for parcial in mudancas.concluidos {
            guard let final = Self.nomeFinal(parcial) else { continue }
            let id = Self.id(final)
            mostrados[id] = nil
            let arquivo = pasta.appendingPathComponent(final)
            mural.receber(Atividade(id: id, titulo: String(localized: "Download concluído"), detalhe: Atividade.limpo(final, ate: 120),
                                    simbolo: "checkmark.circle.fill", cor: "verde", expira: 120, prioridade: "normal")) {
                NSWorkspace.shared.activateFileViewerSelecting([arquivo])
            }
        }
        for parcial in leitura.parciais {
            guard let final = Self.nomeFinal(parcial.nome) else { continue }
            let id = Self.id(final)
            let detalhe = Self.detalhe(nome: final, bytes: parcial.bytes, total: parcial.total)
            guard mostrados[id] != detalhe else { continue }
            mostrados[id] = detalhe
            mural.receber(Atividade(id: id, titulo: String(localized: "Baixando"), detalhe: detalhe,
                                    simbolo: "arrow.down.circle", cor: "azul", expira: 0, prioridade: "baixa"))
        }
        if !mudancas.novos.isEmpty || !mudancas.concluidos.isEmpty || !mudancas.cancelados.isEmpty {
            registro.info("downloads: \(mudancas.novos.count) novos, \(mudancas.concluidos.count) concluídos, \(mudancas.cancelados.count) cancelados")
        }
        return !atuais.isEmpty
    }

    /// Um vigia de sistema de arquivos na pasta: acorda a leitura quando algo entra, sai ou é renomeado.
    /// Aberto só depois de a leitura passar, para não abrir a pasta antes de o macOS liberar.
    private func vigiar() {
        guard vigia == nil else { return }
        let descritor = open(pasta.path, O_EVTONLY)
        guard descritor >= 0 else { return }
        let fonte = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descritor, eventMask: [.write, .rename, .delete],
                                                              queue: .main)
        fonte.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.adiada?.cancel()
                self.adiada = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    self?.verificar()
                }
            }
        }
        fonte.setCancelHandler { close(descritor) }
        fonte.resume()
        vigia = fonte
    }
}
