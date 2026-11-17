import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// A aba do Kanji na ilha aberta: as ações numa linha, como a grade de atalhos, e as skills embaixo.
struct AbaKanji: View {
    let estado: EstadoIlha
    let kanji: PonteKanji
    let mural: Mural

    static let alturaSkills: CGFloat = 44
    static let espaco: CGFloat = 6

    /// Altura do conteúdo da aba, para a ilha se dimensionar.
    static func altura(skills: Int) -> CGFloat { Geometria.alturaKanji(skills: skills) }

    init(estado: EstadoIlha, kanji: PonteKanji, mural: Mural) {
        self.estado = estado
        self.kanji = kanji
        self.mural = mural
    }

    var body: some View {
        Group {
            if kanji.instalado {
                VStack(spacing: Self.espaco) {
                    acoes
                    if !kanji.skills.isEmpty { skills }
                }
            } else {
                Text("Kanji não está instalado")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: Geometria.alturaAtalhos)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .onAppear { kanji.recarregar() }
    }

    private var acoes: some View {
        HStack(spacing: 4) {
            ForEach(kanji.acoes) { acao in
                Button {
                    recolherEntao { kanji.executar(acao) }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: acao.simbolo).font(.system(size: 17, weight: .medium)).frame(height: 22)
                        Text(acao.nome).font(.caption2.weight(.semibold))
                        Text(verbatim: acao.teclas.legenda).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .vidro(raio: 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(Text(acao.ajuda))
            }
        }
        .frame(height: Geometria.alturaAtalhos)
    }

    private var skills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(kanji.skills) { skill in
                    Button {
                        recolherEntao { kanji.executar(skill) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(cor(skill.cor)).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: skill.nome).font(.caption2.weight(.semibold))
                                Text(verbatim: skill.teclas?.legenda ?? "—").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minWidth: 72, maxHeight: .infinity, alignment: .leading)
                        .vidro(raio: 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(skill.teclas == nil)
                    .opacity(skill.teclas == nil ? 0.4 : 1)
                    .help(skill.teclas == nil ? Text("Sem atalho livre: escolha um para esta skill no Kanji")
                                              : Text("Começa um ditado com esta skill"))
                }
            }
        }
        .frame(height: Self.alturaSkills)
    }

    /// A ilha recolhe antes, como na grade de atalhos: o foco e o cursor voltam ao app da pessoa, onde o texto vai cair.
    private func recolherEntao(_ acao: @escaping @MainActor () -> Void) {
        estado.recolher = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            acao()
        }
    }

    private func cor(_ nome: String) -> Color {
        switch nome {
        case "verde": .green
        case "azul": .blue
        case "roxo": .purple
        case "rosa": .pink
        case "ciano": .cyan
        case "amarelo": .yellow
        default: .white
        }
    }
}
