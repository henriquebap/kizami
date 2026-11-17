import Foundation

// Atalhos da Apple: leitura da `shortcuts list`, escolhidos × disponíveis, escolher e ordenar. Nenhum atalho roda aqui.
@MainActor func testarAtalhosApple() {
    let saida = "Abrir o diário\r\n  Foco  \n\n   \nAbrir o diário\n-h\nModo reunião 🎧\n"
    conferir("uma linha por atalho, sem vazias, espaços nem repetidos", AtalhosApple.ler(saida),
             ["Abrir o diário", "Foco", "-h", "Modo reunião 🎧"])
    conferir("saída vazia", AtalhosApple.ler(""), [])
    conferir("teto da lista", AtalhosApple.ler((1...600).map { "a\($0)" }.joined(separator: "\n")).count,
             AtalhosApple.maximoNaLista)

    let disponiveis = ["A", "B", "C"]
    conferir("tira o que não existe mais, mantém a ordem da pessoa",
             AtalhosApple.conciliar(["C", "Sumiu", "A"], disponiveis: disponiveis), ["C", "A"])
    conferir("sem lista lida, não tira nada", AtalhosApple.conciliar(["C", "Sumiu"], disponiveis: nil), ["C", "Sumiu"])
    conferir("sem vazio nem repetido", AtalhosApple.conciliar(["A", "", "A", "B"], disponiveis: nil), ["A", "B"])
    conferir("no máximo 6", AtalhosApple.conciliar((1...9).map { "\($0)" }, disponiveis: nil).count, 6)

    conferir("escolhe no fim", AtalhosApple.alternado(["A"], "B"), ["A", "B"])
    conferir("desescolhe", AtalhosApple.alternado(["A", "B"], "A"), ["B"])
    let cheio = (1...6).map { "\($0)" }
    conferir("cheio não escolhe mais", AtalhosApple.alternado(cheio, "7"), cheio)
    conferir("cheio ainda desescolhe", AtalhosApple.alternado(cheio, "6"), ["1", "2", "3", "4", "5"])
    conferir("nome vazio não entra", AtalhosApple.alternado([], ""), [])

    conferir("nome com hífen nunca vira opção", AtalhosApple.argumentos(rodar: "-h"), ["run", "--", "-h"])
    conferir("nome é um argumento só", AtalhosApple.argumentos(rodar: "a; rm -rf ~ --input-path x"),
             ["run", "--", "a; rm -rf ~ --input-path x"])

    conferir("sobe uma posição", AtalhosApple.subido(["A", "B", "C"], "C"), ["A", "C", "B"])
    conferir("o primeiro fica", AtalhosApple.subido(["A", "B"], "A"), ["A", "B"])
    conferir("quem não está não mexe", AtalhosApple.subido(["A", "B"], "Z"), ["A", "B"])
}
