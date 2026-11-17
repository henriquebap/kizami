import Foundation

@MainActor func testarDownloads() {
    // Parciais e nome final
    conferir("chrome", Downloads.nomeFinal("relatorio.pdf.crdownload"), "relatorio.pdf")
    conferir("safari", Downloads.nomeFinal("foto.zip.download"), "foto.zip")
    conferir("firefox", Downloads.nomeFinal("video.mp4.part"), "video.mp4")
    conferir("maiúsculas", Downloads.nomeFinal("A.ZIP.CRDOWNLOAD"), "A.ZIP")
    conferir("arquivo comum não é parcial", Downloads.nomeFinal("relatorio.pdf"), nil)
    conferir("só o sufixo não é parcial", Downloads.nomeFinal(".part"), nil)

    // Detalhe
    conferir("porcentagem", Downloads.detalhe(nome: "foto.zip", bytes: 62, total: 100), "foto.zip · 62%")
    conferir("porcentagem nunca passa de 100", Downloads.detalhe(nome: "a", bytes: 150, total: 100), "a · 100%")
    let tamanho = Downloads.detalhe(nome: "video.mp4", bytes: 45_000_000, total: nil)
    conferir("tamanho sem total", tamanho.hasPrefix("video.mp4 · 45") && tamanho.hasSuffix("MB"), true)
    conferir("total desconhecido vira tamanho", Downloads.detalhe(nome: "a", bytes: 0, total: -1).hasSuffix("%"), false)
    conferir("nome de site sem controle nem direção", Downloads.detalhe(nome: "ab\u{202E}c\n.pdf", bytes: 1, total: 2), "abc.pdf · 50%")
    let longo = Downloads.detalhe(nome: String(repeating: "x", count: 500), bytes: 1, total: 4)
    conferir("nome longo não engole a porcentagem", longo.hasSuffix(" · 25%") && longo.count <= 120, true)

    // Info.plist do Safari
    let safari = Downloads.progressoDoSafari(["DownloadEntryProgressBytesSoFar": 300, "DownloadEntryProgressTotalToLoad": 1200])
    conferir("safari: bytes", safari?.bytes, 300)
    conferir("safari: total", safari?.total, 1200)
    conferir("safari: total -1 é desconhecido",
             Downloads.progressoDoSafari(["DownloadEntryProgressBytesSoFar": 10, "DownloadEntryProgressTotalToLoad": -1])?.total, nil)
    conferir("safari: sem bytes", Downloads.progressoDoSafari(["DownloadEntryURL": "https://exemplo.invalid"]) == nil, true)
    conferir("safari: bytes de outro tipo", Downloads.progressoDoSafari(["DownloadEntryProgressBytesSoFar": "300"]) == nil, true)

    // Decisão entre duas leituras
    let decisao = Downloads.decidir(
        antes: ["a.zip.crdownload", "b.pdf.part", "c.dmg.download", "d.mp4.part"],
        parciais: ["b.pdf.part", "e.txt.crdownload"],
        nomes: ["b.pdf.part", "b.pdf", "e.txt.crdownload", "a.zip", "d.mp4.part", "d.mp4"])
    conferir("novos", decisao.novos, ["e.txt.crdownload"])
    conferir("em andamento", decisao.andamento, ["b.pdf.part"])
    conferir("concluído: sumiu e o final apareceu", decisao.concluidos, ["a.zip.crdownload"])
    // c sumiu sem arquivo; d parou (está na pasta, fora dos ativos) e o final vazio do Firefox não conta como concluído
    conferir("cancelados", decisao.cancelados, ["c.dmg.download", "d.mp4.part"])
    conferir("primeira leitura não conclui nada",
             Downloads.decidir(antes: [], parciais: [], nomes: ["a.zip"]), MudancasDeDownload())

    // Id
    conferir("id estável", Downloads.id("a.zip"), Downloads.id("a.zip"))
    conferir("id por arquivo", Downloads.id("a.zip") != Downloads.id("b.zip"), true)
    conferir("id com prefixo", Downloads.id("a.zip").hasPrefix("download-"), true)

    // Leitura de uma pasta de rascunho
    let fm = FileManager.default
    let pasta = fm.temporaryDirectory.appendingPathComponent("kizami-downloads-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: pasta) }
    try? fm.createDirectory(at: pasta, withIntermediateDirectories: true)
    fm.createFile(atPath: pasta.appendingPathComponent("a.zip.crdownload").path, contents: Data(count: 2048))
    fm.createFile(atPath: pasta.appendingPathComponent("velho.iso.part").path, contents: Data(count: 10),
                  attributes: [.modificationDate: Date.now.addingTimeInterval(-3600)])
    fm.createFile(atPath: pasta.appendingPathComponent("falso.download").path, contents: Data(count: 1))
    fm.createFile(atPath: pasta.appendingPathComponent("pronto.pdf").path, contents: Data())
    // `.part` sem o arquivo final ao lado é de outra coisa (arquivo dividido, rsync); com ele, é o Firefox.
    fm.createFile(atPath: pasta.appendingPathComponent("backup.tar.part").path, contents: Data(count: 10))
    fm.createFile(atPath: pasta.appendingPathComponent("video.mp4.part").path, contents: Data(count: 300))
    fm.createFile(atPath: pasta.appendingPathComponent("video.mp4").path, contents: Data())
    let pacote = pasta.appendingPathComponent("foto.jpg.download")
    try? fm.createDirectory(at: pacote, withIntermediateDirectories: true)
    fm.createFile(atPath: pacote.appendingPathComponent("foto.jpg").path, contents: Data(count: 500))
    (["DownloadEntryProgressBytesSoFar": 500, "DownloadEntryProgressTotalToLoad": 2000] as NSDictionary)
        .write(to: pacote.appendingPathComponent("Info.plist"), atomically: true)

    let lida = Downloads.ler(pasta)
    conferir("leitura: todos os nomes", lida?.nomes.count, 8)
    let parciais = (lida?.parciais ?? []).sorted { $0.nome < $1.nome }
    conferir("leitura: parciais ativos (sem o parado nem o .download que é arquivo)",
             parciais, [Parcial(nome: "a.zip.crdownload", bytes: 2048, total: nil),
                        Parcial(nome: "foto.jpg.download", bytes: 500, total: 2000),
                        Parcial(nome: "video.mp4.part", bytes: 300, total: nil)])
    conferir("leitura: pasta que não existe", Downloads.ler(pasta.appendingPathComponent("nada")) == nil, true)
}
