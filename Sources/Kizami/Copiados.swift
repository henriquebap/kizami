import AppKit
import ImageIO
import Observation

/// Um texto ou uma imagem copiados. Só existe na memória do app: nunca vai para disco, `UserDefaults` nem log.
struct ItemCopiado: Identifiable, Equatable, Sendable {
    enum Conteudo: Equatable, Sendable {
        case texto(String)
        case imagem(Imagem)
    }

    /// Os bytes como vieram da área de transferência (PNG ou TIFF), sem reprocessar: colar devolve o mesmo arquivo.
    struct Imagem: Equatable, Sendable {
        let dados: Data
        let tipo: String  // "public.png" ou "public.tiff", para colar com o tipo certo
        let largura: Int
        let altura: Int
        /// Feita uma vez na cópia: decodificar a imagem inteira a cada redesenho da linha travaria a ilha.
        let miniatura: CGImage?

        /// Igualdade pelos bytes: duas cópias da mesma imagem são o mesmo item, e a miniatura não conta.
        static func == (a: Imagem, b: Imagem) -> Bool { a.tipo == b.tipo && a.dados == b.dados }
    }

    let id: UUID
    let conteudo: Conteudo
    let data: Date

    static let tamanhoResumo = 80

    /// O que o item ocupa na memória, para o teto total do histórico.
    var bytes: Int {
        switch conteudo {
        case .texto(let texto): texto.utf8.count
        case .imagem(let imagem): imagem.dados.count
        }
    }

    /// Texto: uma linha só, quebras e espaços seguidos viram um espaço, e o texto longo para em `tamanhoResumo`.
    /// O corte poupa o SwiftUI de medir 2.000 caracteres para mostrar uns 40. Imagem: nada (a linha mostra o tamanho).
    var resumo: String {
        guard case .texto(let texto) = conteudo else { return "" }
        let linha = texto.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return linha.count > Self.tamanhoResumo ? linha.prefix(Self.tamanhoResumo - 1) + "…" : linha
    }
}

/// O histórico da área de transferência, desligado por padrão: os últimos textos e imagens copiados, para colar
/// de novo num clique. Mesmos filtros do histórico do Kanji, mas sem arquivo: some ao fechar o app.
@MainActor @Observable
final class Copiados {
    static let chaveLigado = "copiados.ligado"
    static let maximo = 10
    /// Texto maior fica de fora em vez de cortado: colar metade de um texto seria pior que não oferecer.
    static let limiteTexto = 2_000
    /// Uma captura de tela Retina em PNG fica em 2 a 6 MB; 10 MB cobre isso e recusa o TIFF sem compressão de uma
    /// foto grande, que não vale guardar num histórico de colar.
    static let limiteImagem = 10 * 1_024 * 1_024
    /// Teto da lista inteira na memória. Dez imagens no limite seriam 100 MB num app de barra de menus que vive com
    /// algumas dezenas; 50 MB ainda guarda umas dez capturas comuns, e o que passa sai pela imagem mais antiga.
    static let limiteTotal = 50 * 1_024 * 1_024

    private(set) var itens: [ItemCopiado] = []

    /// Só o booleano vai para o `UserDefaults`. Desligar esquece tudo na hora.
    var ligado = UserDefaults.standard.bool(forKey: Copiados.chaveLigado) {
        didSet {
            guard ligado != oldValue else { return }
            UserDefaults.standard.set(ligado, forKey: Self.chaveLigado)
            registro.info("copiados: \(self.ligado ? "ligado" : "desligado", privacy: .public)")
            if ligado { iniciar() } else { parar() }
        }
    }

    @ObservationIgnored private var ultimoChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var vigia: Task<Void, Never>?

    init() {}

    /// O macOS não avisa mudanças na área de transferência; todo gerenciador consulta o `changeCount`.
    // ponytail: consulta a cada 0,5 s enquanto ligado, como o Kanji; é uma leitura de inteiro, barata.
    func iniciar() {
        guard ligado, vigia == nil else { return }
        // O que já estava copiado antes de ligar não entra: ligar não é dar permissão retroativa.
        ultimoChangeCount = NSPasteboard.general.changeCount
        vigia = Task { [weak self] in
            while !Task.isCancelled {
                self?.conferir()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Põe o item na área de transferência e manda ⌘V para o app em que a pessoa está (a ilha nunca toma o foco).
    /// Sem Acessibilidade, pede uma vez e o item fica copiado para a pessoa colar ela mesma.
    func colar(_ item: ItemCopiado) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.conteudo {
        case .texto(let texto): pb.setString(texto, forType: .string)
        case .imagem(let imagem): pb.setData(imagem.dados, forType: NSPasteboard.PasteboardType(imagem.tipo))
        }
        ultimoChangeCount = pb.changeCount  // a própria escrita não volta como item novo
        itens = Self.incluir(item.conteudo, em: itens, agora: .now)
        guard CGPreflightPostEventAccess() else {
            CGRequestPostEventAccess()
            registro.notice("copiados: sem permissão para mandar ⌘V; o item ficou copiado")
            return
        }
        let fonte = CGEventSource(stateID: .hidSystemState)
        for apertada in [true, false] {
            let evento = CGEvent(keyboardEventSource: fonte, virtualKey: 0x09, keyDown: apertada)  // kVK_ANSI_V
            evento?.flags = .maskCommand
            evento?.post(tap: .cghidEventTap)
        }
        registro.info("copiados: colado")
    }

    func remover(_ item: ItemCopiado) {
        itens = itens.filter { $0.id != item.id }
    }

    func esvaziar() {
        itens = []
    }

    private func parar() {
        vigia?.cancel()
        vigia = nil
        esvaziar()
    }

    private func conferir() {
        let pb = NSPasteboard.general
        guard pb.changeCount != ultimoChangeCount else { return }
        ultimoChangeCount = pb.changeCount
        let tipos = pb.types?.map(\.rawValue) ?? []
        guard let novo = lerTexto(pb, tipos: tipos) ?? lerImagem(pb, tipos: tipos) else {
            registro.debug("copiados: cópia ignorada")
            return
        }
        itens = Self.incluir(novo, em: itens, agora: .now)
        registro.debug("copiados: \(self.itens.count) itens")
    }

    private func lerTexto(_ pb: NSPasteboard, tipos: [String]) -> ItemCopiado.Conteudo? {
        // Mede antes de virar String: copiar dezenas de MB travaria a ilha, que roda na mesma thread.
        guard (pb.data(forType: .string)?.count ?? 0) <= 4 * Self.limiteTexto,
              let texto = pb.string(forType: .string), Self.aceitar(tipos: tipos, texto: texto) else { return nil }
        return .texto(texto)
    }

    // ponytail: a miniatura é feita na thread principal; um PNG de 10 MB leva umas dezenas de ms. Passar para uma
    // Task fora da principal se a ilha engasgar ao copiar imagens grandes.
    private func lerImagem(_ pb: NSPasteboard, tipos: [String]) -> ItemCopiado.Conteudo? {
        // O tamanho é medido nos bytes antes de qualquer decodificação; a área de transferência não diz o tamanho
        // sem entregar os dados.
        guard let tipo = Self.tipoDeImagem(tipos), let dados = pb.data(forType: NSPasteboard.PasteboardType(tipo)),
              let imagem = Self.imagem(dados, tipo: tipo) else { return nil }
        return .imagem(imagem)
    }

    // MARK: Regras puras

    /// Convenção nspasteboard.org: gerenciadores de senha marcam o conteúdo como Concealed/Transient/AutoGenerated
    /// (e o 1Password também com o próprio tipo). Arquivo copiado no Finder também traz o nome como texto:
    /// colar o nome no lugar do arquivo confundiria, então fica de fora.
    private static let tiposRecusados: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword", "public.file-url",
    ]

    static func aceitar(tipos: [String], texto: String) -> Bool {
        tiposRecusados.isDisjoint(with: tipos)
            && texto.count <= limiteTexto
            && !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pareceSegredo(texto)
    }

    /// Imagem só quando a cópia não traz texto. Planilhas, Keynote e editores de texto rico mandam junto uma foto
    /// do trecho copiado; quem copia células quer colar o conteúdo, não a foto. E texto recusado (senha, chave) não
    /// cai para a imagem que veio com ele. PNG antes de TIFF: é o mesmo desenho em bem menos bytes.
    static func tipoDeImagem(_ tipos: [String]) -> String? {
        guard tiposRecusados.isDisjoint(with: tipos), !tipos.contains("public.utf8-plain-text") else { return nil }
        return ["public.png", "public.tiff"].first(where: tipos.contains)
    }

    /// Valida os bytes de fora: dentro do teto, e uma imagem que o ImageIO consegue ler. Lê só o cabeçalho para a
    /// largura e a altura; a miniatura sai com 44 px, o dobro dos 22 pt da linha, para telas Retina.
    static let limitePixels = 64_000_000

    // ponytail: `pb.data(forType:)` materializa a imagem inteira antes do teto de bytes; o macOS não diz o tamanho
    // antes de entregar. Um TIFF de centenas de MB pesa por um instante e é recusado; ler em pedaços se incomodar.
    static func imagem(_ dados: Data, tipo: String) -> ItemCopiado.Imagem? {
        guard !dados.isEmpty, dados.count <= limiteImagem,
              let fonte = CGImageSourceCreateWithData(dados as CFData, nil),
              let propriedades = CGImageSourceCopyPropertiesAtIndex(fonte, 0, nil) as? [CFString: Any],
              let largura = propriedades[kCGImagePropertyPixelWidth] as? Int,
              let altura = propriedades[kCGImagePropertyPixelHeight] as? Int, largura > 0, altura > 0,
              // Os 10 MB são comprimidos: um PNG desse tamanho pode ter 100+ megapixels, e a miniatura decodifica
              // tudo na thread da ilha. Acima de 64 MP (uma foto de câmera tem 12 a 48), fica de fora.
              largura.multipliedReportingOverflow(by: altura).partialValue <= Self.limitePixels,
              !largura.multipliedReportingOverflow(by: altura).overflow else { return nil }
        let opcoes: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: 44]
        return ItemCopiado.Imagem(dados: dados, tipo: tipo, largura: largura, altura: altura,
                                  miniatura: CGImageSourceCreateThumbnailAtIndex(fonte, 0, opcoes as CFDictionary))
    }

    /// O mais novo em cima, sem repetidos (copiar de novo sobe o item, com o mesmo id), no máximo `maximo` itens e
    /// `limiteBytes` somados. Quem não cabe no teto de bytes sai, do mais antigo para trás: na prática, só imagens,
    /// já que um texto tem no máximo uns KB, e os textos mais antigos ficam.
    static func incluir(_ novo: ItemCopiado.Conteudo, em itens: [ItemCopiado], agora: Date,
                        maximo: Int = Copiados.maximo, limiteBytes: Int = Copiados.limiteTotal) -> [ItemCopiado] {
        let id = itens.first { $0.conteudo == novo }?.id ?? UUID()
        var total = 0
        var lista: [ItemCopiado] = []
        for item in [ItemCopiado(id: id, conteudo: novo, data: agora)] + itens.filter({ $0.conteudo != novo }) {
            guard lista.count < maximo else { break }
            guard total + item.bytes <= limiteBytes else { continue }
            total += item.bytes
            lista.append(item)
        }
        return lista
    }

    /// Chave de API, token ou URL com senha em qualquer parte do texto ("export KEY=…", "Bearer …", um .env).
    /// Sites como o Console da Anthropic não marcam a cópia como Concealed, então o tipo não basta
    /// (no Kanji, uma chave foi parar no histórico assim). Mesma regra do `Historico.pareceSegredo` do Kanji.
    // ponytail: heurística; hash e UUID longos também ficam de fora, o que é aceitável para um histórico
    private static func pareceSegredo(_ texto: String) -> Bool {
        let palavras = texto.split(whereSeparator: \.isWhitespace)
        if palavras.count == 1, let unica = palavras.first, pareceSenha(unica) { return true }
        return palavras.contains { palavra in
            if let esquema = palavra.range(of: "://"),
               palavra[esquema.upperBound...].split(separator: "/").first?.contains("@") == true { return true }  // usuario:senha@host
            // KEY=valor, e os pedaços de uma URL: `?access_token=…`, link mágico, URL assinada.
            return palavra.split(whereSeparator: { "=&?#/:".contains($0) }).contains { valor in
                valor.count >= 32 && valor.contains(where: \.isNumber) && valor.contains(where: \.isLetter)
            }
        }
    }

    /// Uma palavra só com cara de senha curta (8 a 31 caracteres misturando três classes) ou um código de 4 a 8
    /// dígitos (2FA): sites que não marcam a cópia como Concealed. Perde alguns textos legítimos; é um histórico.
    private static func pareceSenha(_ palavra: Substring) -> Bool {
        if (4...8).contains(palavra.count) && palavra.allSatisfy(\.isNumber) { return true }
        guard (8...31).contains(palavra.count), !palavra.contains("://"), !palavra.contains("@") else { return false }
        let classes = [palavra.contains(where: \.isLowercase), palavra.contains(where: \.isUppercase),
                       palavra.contains(where: \.isNumber), palavra.contains(where: { !$0.isLetter && !$0.isNumber })]
        return classes.filter { $0 }.count >= 3
    }
}
