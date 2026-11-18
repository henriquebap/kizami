import SwiftUI

/// O dia calmo (v0.16): nada pede atenção, então a ilha mostra o dia. Em cima, a data e a temperatura grandes e a
/// frase que responde "estou livre?"; no meio, a régua das 8h às 20h com os eventos na cor do calendário, a chuva
/// prevista e o agora; embaixo, o que ainda falta hoje. Clique: a agenda expande no lugar.
struct CartaoDia: View {
    let agenda: Agenda
    let tempo: Tempo
    let estado: EstadoIlha
    /// O fundo cresce até a agenda expandida (mesmo id).
    let espaco: Namespace.ID
    let aoClicar: () -> Void

    var body: some View {
        // Por minuto: o agora anda na régua, a frase muda quando uma reunião começa, a data vira à meia-noite.
        // Só enquanto a ilha está aberta, que é quando o cartão existe.
        TimelineView(.everyMinute) { contexto in conteudo(agora: contexto.date) }
            .padding(Painel.folga)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cartao(raio: Painel.raio, realce: estado.cartaoSobCursor == "dia", id: "agenda", em: espaco)
            .contentShape(.rect)
            .realce("dia", estado)
            .onTapGesture(perform: aoClicar)
            .accessibilityAddTraits(.isButton)
    }

    private func conteudo(agora: Date) -> some View {
        let previsao = tempo.previsao
        return VStack(alignment: .leading, spacing: Painel.espaco) {
            // A cabeça tem a altura da linha de destaque dos outros cartões largos: a data e a temperatura no tamanho
            // dos números da grade, e uma linha de texto embaixo de cada uma.
            HStack(alignment: .top, spacing: Painel.folga) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: Self.data(agora)).font(Tipo.numero).lineLimit(1).minimumScaleFactor(0.7)
                    Text(verbatim: frase(agora: agora, previsao: previsao))
                        .font(Tipo.corpo).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
                if let previsao {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: previsao.simbolo).symbolRenderingMode(.multicolor).font(.system(size: 20))
                            .frame(height: 29)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: Previsao.graus(previsao.temperatura)).font(Tipo.numero)
                            Text(verbatim: "↑\(Previsao.graus(previsao.maxima)) ↓\(Previsao.graus(previsao.minima))")
                                .font(Tipo.corpo).foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                    }
                    .fixedSize()
                    .help(Text(verbatim: [previsao.descricao, tempo.local].compactMap { $0 }.joined(separator: "\n")))
                }
            }
            .frame(height: Painel.linhaDeDestaque, alignment: .top)
            ReguaDoDia(eventos: agenda.hoje,
                       chuva: previsao.map { Previsao.faixasDeChuva($0.horas, dia: agora, calendario: .current) } ?? [],
                       agora: agora)
                .frame(height: Painel.reguaDoDia)
            if !agenda.hoje.isEmpty {
                VStack(spacing: 0) {
                    ForEach(agenda.hoje.prefix(3)) { evento in
                        LinhaDoDia(evento: evento) { agenda.entrar(evento) }.frame(height: Painel.linhaDoDia)
                    }
                }
            }
        }
    }

    /// "Terça-feira, 17": o dia da semana por extenso, que é o que se procura de relance, com a inicial maiúscula.
    static func data(_ agora: Date) -> String {
        let texto = agora.formatted(.dateTime.weekday(.wide).day())
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }

    /// Sem acesso à agenda não dá para dizer se está livre: a descrição do tempo no lugar.
    private func frase(agora: Date, previsao: Previsao?) -> String {
        guard agenda.acesso == .permitido else { return previsao?.descricao ?? "" }
        return Self.frase(EventoAgenda.resumo(agenda.hoje, agora: agora))
    }

    static func frase(_ resumo: ResumoDoDia) -> String {
        let hora = { (data: Date) in data.formatted(date: .omitted, time: .shortened) }
        let principal = switch resumo.estado {
        case .emReuniao(let titulo, let ate): String(localized: "Em \(titulo) até \(hora(ate))")
        case .chegando(let titulo, let minutos, let livreAte?):
            String(localized: "\(titulo) em \(minutos) min, depois livre até \(hora(livreAte))")
        case .chegando(let titulo, let minutos, nil): String(localized: "\(titulo) em \(minutos) min")
        case .livreAte(let data): String(localized: "Livre até \(hora(data))")
        case .livreORestoDoDia: String(localized: "Livre o resto do dia")
        }
        return resumo.depois > 0 ? principal + " · " + String(localized: "mais \(resumo.depois) hoje") : principal
    }
}

/// A régua do dia, das 8h às 20h: os eventos em blocos na cor do calendário, a chuva provável em faixa azul e uma
/// linha branca no agora. Fora dessas horas, o que passa da borda é cortado.
private struct ReguaDoDia: View {
    let eventos: [EventoAgenda]
    let chuva: [FaixaDeChuva]
    let agora: Date
    private static let primeira = 8
    private static let horas = 12

    var body: some View {
        let inicio = Calendar.current.date(bySettingHour: Self.primeira, minute: 0, second: 0, of: agora) ?? agora
        let duracao = TimeInterval(Self.horas * 3600)
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                ForEach(Array(stride(from: Self.primeira, through: Self.primeira + Self.horas, by: 2)), id: \.self) { h in
                    Text(verbatim: "\(h)h")
                    if h < Self.primeira + Self.horas { Spacer(minLength: 0) }
                }
            }
            .font(Tipo.legenda).monospacedDigit().foregroundStyle(.tertiary)
            GeometryReader { caixa in
                let largura = caixa.size.width
                let x = { (data: Date) in CGFloat(min(max(data.timeIntervalSince(inicio) / duracao, 0), 1)) * largura }
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08)).frame(height: 6)
                    ForEach(Array(chuva.enumerated()), id: \.offset) { _, faixa in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.blue.opacity(0.28))
                            .frame(width: max(x(faixa.fim) - x(faixa.inicio), 4), height: 18)
                            .offset(x: x(faixa.inicio))
                            .help(Text(verbatim: String(localized: "Chance de chuva: \("\(faixa.maxima)%")")))
                    }
                    ForEach(eventos.filter { !$0.diaInteiro && $0.fim > inicio && $0.inicio < inicio + duracao }) { evento in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(corDoCalendario(evento))
                            .frame(width: max(x(evento.fim) - x(evento.inicio), 5), height: 12)
                            .offset(x: x(evento.inicio))
                            .help(Text(verbatim: evento.titulo))  // verbatim: o título vem do convite
                    }
                    if agora > inicio && agora < inicio + duracao {
                        Capsule().fill(.white)
                            .frame(width: 2, height: 22)
                            .shadow(color: .black.opacity(0.8), radius: 1)
                            .offset(x: x(agora) - 1)
                    }
                }
                .frame(width: largura, height: 22)
            }
            .frame(height: 22)
        }
    }
}

/// Um evento que falta hoje: o ponto na cor do calendário, a hora, o título e o Entrar quando há link.
private struct LinhaDoDia: View {
    let evento: EventoAgenda
    let entrar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(corDoCalendario(evento)).frame(width: 7, height: 7)
            Text(verbatim: evento.diaInteiro ? String(localized: "Dia inteiro")
                 : evento.inicio.formatted(date: .omitted, time: .shortened))
                .font(Tipo.corpo).monospacedDigit().foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .leading)
                .fixedSize()
            // verbatim: o título vem do convite de qualquer pessoa.
            Text(verbatim: evento.titulo).font(Tipo.titulo).lineLimit(1)
            Spacer(minLength: 4)
            if evento.link != nil { BotaoEntrar(acao: entrar) }
        }
    }
}
