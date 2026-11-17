import SwiftUI

/// O widget do próximo evento: a hora grande (ou quanto falta, na última hora), o título e, se houver link de
/// reunião, o botão de entrar. Clique: a agenda expande no lugar. Sem evento (ou sem permissão), não ocupa nada.
struct WidgetAgenda: View {
    let agenda: Agenda
    let estado: EstadoIlha
    let espaco: Namespace.ID
    let aoClicar: () -> Void

    var body: some View {
        if let evento = agenda.proximo {
            Quadro(id: "agenda", estado: estado, acao: aoClicar, espaco: espaco) {
                Cabeca(rotulo: Text("Próximo"), ponto: corDoCalendario(evento))
                // Por minuto: "12 min" precisa andar sozinho, sem a Agenda publicar nada.
                TimelineView(.everyMinute) { contexto in
                    Text(verbatim: Self.quando(evento, agora: contexto.date))
                        .font(Tipo.numero).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    // verbatim: o título vem do convite de qualquer pessoa e não pode virar Markdown nem chave de tradução.
                    Text(verbatim: evento.titulo).font(Tipo.corpo).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if evento.link != nil { BotaoEntrar { agenda.entrar(evento) } }
                }
            }
        }
    }

    /// Hora exata para o que está longe; contagem na última hora, quando "quanto falta" importa mais que "a que horas".
    static func quando(_ evento: EventoAgenda, agora: Date) -> String {
        let falta = evento.inicio.timeIntervalSince(agora)
        if falta <= 0 { return String(localized: "agora") }
        if falta < 3600 { return String(localized: "\(Int((falta / 60).rounded(.up))) min") }
        return evento.inicio.formatted(date: .omitted, time: .shortened)
    }
}

/// A reunião dos próximos 15 min em destaque, como uma Live Activity: quanto falta em número grande, na cor do
/// calendário, e o botão de entrar largo, que é a única coisa a fazer agora.
struct CartaoReuniao: View {
    let agenda: Agenda
    let espaco: Namespace.ID

    var body: some View {
        if let evento = agenda.emBreve {
            let cor = corDoCalendario(evento)
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(cor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(cor.opacity(0.22)))
                        .matchedGeometryEffect(id: "reuniao", in: espaco)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reunião").estiloRotulo(cor)
                        Text(verbatim: evento.titulo).font(Tipo.titulo).lineLimit(1)
                        Text(verbatim: AbaHoje.horario(evento)).font(Tipo.corpo).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    TimelineView(.everyMinute) { contexto in
                        let minutos = Int((evento.inicio.timeIntervalSince(contexto.date) / 60).rounded(.up))
                        VStack(alignment: .trailing, spacing: 0) {
                            if minutos > 0 {
                                Text(verbatim: "\(minutos)").font(Tipo.destaque).monospacedDigit().foregroundStyle(cor)
                                Text("min").estiloRotulo()
                            } else {
                                Text("agora").font(Tipo.numeroPequeno).foregroundStyle(cor)
                            }
                        }
                    }
                }
                if evento.link != nil {
                    Button { agenda.entrar(evento) } label: {
                        Label("Entrar na reunião", systemImage: "video.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .background(Capsule().fill(.green))
                            .foregroundStyle(.black.opacity(0.85))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(EstiloBotao())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .cartao(cor: cor, raio: Geometria.raioDoWidget)
        }
    }
}

/// A aba "Hoje": o resto do dia, um evento por linha, com o botão de entrar quando há link de reunião.
struct AbaHoje: View {
    let agenda: Agenda

    var body: some View {
        let eventos = agenda.hoje
        let maximo = Geometria.maximoDoDia
        let visiveis = eventos.count > maximo ? maximo - 1 : maximo
        VStack(alignment: .leading, spacing: Geometria.espacoLinha) {
            if agenda.acesso == .negado {
                Button { Kizami.shared.abrirAjustes() } label: {
                    Label("Liberar o calendário nos Ajustes", systemImage: "calendar.badge.exclamationmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(height: Geometria.alturaLinha)
            } else if eventos.isEmpty {
                Label("Nada mais na agenda hoje", systemImage: "calendar")
                    .foregroundStyle(.secondary)
                    .frame(height: Geometria.alturaLinha)
            }
            ForEach(eventos.prefix(visiveis)) { evento in
                HStack(spacing: 10) {
                    Capsule()
                        .fill(evento.cor.map { Color(red: $0.x, green: $0.y, blue: $0.z) } ?? .red)
                        .frame(width: 3, height: 22)
                    Text(verbatim: Self.horario(evento))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .frame(minWidth: 84, alignment: .leading)  // "10:00 AM–11:30 AM" em inglês passa de 84
                        .fixedSize()
                    // verbatim: o título vem do convite de qualquer pessoa.
                    Text(verbatim: evento.titulo).font(.callout.weight(.semibold))
                    Spacer(minLength: 4)
                    if evento.link != nil {
                        Button("Entrar") { agenda.entrar(evento) }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.green.opacity(0.85)))
                            .contentShape(.capsule)
                            .fixedSize()
                    }
                }
                .lineLimit(1)
                .frame(height: Geometria.alturaLinha)
            }
            if eventos.count > visiveis {
                Text(String(localized: "mais \(eventos.count - visiveis)"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: Geometria.alturaLinha)
                    .padding(.leading, 13)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    static func horario(_ evento: EventoAgenda) -> String {
        if evento.diaInteiro { return String(localized: "Dia inteiro") }
        let hora = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(evento.inicio.formatted(hora))–\(evento.fim.formatted(hora))"
    }
}

/// A altura da agenda expandida agora: a semana ou o mês do dia escolhido e quantos eventos ele tem.
/// A janela mede a área do hover com a mesma conta (`tamanhoAberto`).
@MainActor func alturaDaAgendaExpandida(_ estado: EstadoIlha, _ agenda: Agenda) -> CGFloat {
    let calendario = Calendar.current
    let dia = estado.diaEscolhido ?? .now
    let semanas = estado.mesInteiro ? Calendario.mes(de: dia, calendario: calendario).count / 7 : 1
    let eventos = Calendario.eventos(agenda.doPeriodo, em: dia, calendario: calendario).count
    return Geometria.alturaAgenda(semanas: semanas, eventos: eventos)
}

func corDoCalendario(_ evento: EventoAgenda?) -> Color {
    evento?.cor.map { Color(red: $0.x, green: $0.y, blue: $0.z) } ?? .red
}

/// A agenda que cresceu do chip: a semana (ou o mês) com um ponto nos dias com evento, e os eventos do dia escolhido.
struct AgendaExpandida: View {
    let estado: EstadoIlha
    let agenda: Agenda
    let espaco: Namespace.ID
    let aoRecolher: () -> Void

    var body: some View {
        let calendario = Calendar.current
        let dia = calendario.startOfDay(for: estado.diaEscolhido ?? .now)
        let dias = estado.mesInteiro ? Calendario.mes(de: dia, calendario: calendario)
                                     : Calendario.semana(de: dia, calendario: calendario)
        let pontos = Calendario.pontos(agenda.doPeriodo, dias: dias, calendario: calendario)
        let eventos = Calendario.eventos(agenda.doPeriodo, em: dia, calendario: calendario)
        VStack(alignment: .leading, spacing: 8) {
            topo(dia)
            if estado.mesInteiro {
                grade(dias, dia: dia, pontos: pontos, calendario: calendario)
            } else {
                faixa(dias, dia: dia, pontos: pontos, calendario: calendario)
            }
            lista(eventos)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(height: Geometria.alturaAgenda(semanas: dias.count / 7, eventos: eventos.count), alignment: .top)
        .cartao(id: "agenda", em: espaco)
        .padding(.horizontal, 4)
    }

    /// O mês e o ano (clique recolhe), Semana/Mês e a seta de recolher.
    private func topo(_ dia: Date) -> some View {
        HStack(spacing: 8) {
            // verbatim: o nome do mês já vem traduzido do sistema.
            Text(verbatim: dia.formatted(.dateTime.month(.wide).year()))
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .onTapGesture(perform: aoRecolher)
            Picker("Ver", selection: Binding(get: { estado.mesInteiro }, set: { novo in
                withAnimation(Movimento.ou(Movimento.expandir)) { estado.mesInteiro = novo }
            })) {
                Text("Semana").tag(false)
                Text("Mês").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Button("Recolher", systemImage: "chevron.up", action: aoRecolher)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
                .help(Text("Recolher"))
        }
        .frame(height: 24)
    }

    /// A semana numa fileira: a letra do dia, o número e o ponto.
    private func faixa(_ dias: [Date], dia: Date, pontos: [Date: EventoAgenda], calendario: Calendar) -> some View {
        let letras = Calendario.letras(calendario: calendario)
        return HStack(spacing: 2) {
            ForEach(Array(dias.enumerated()), id: \.offset) { i, d in
                Button { escolher(d) } label: {
                    VStack(spacing: 2) {
                        Text(verbatim: letras[i % 7]).font(.caption2).foregroundStyle(.secondary)
                        numero(d, calendario: calendario)
                        ponto(pontos[d])
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(selecao(d == dia))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: Geometria.alturaDaFaixa)
    }

    /// O mês em fileiras de 7, com as letras em cima. Os dias de fora do mês ficam apagados, mas abrem também.
    private func grade(_ dias: [Date], dia: Date, pontos: [Date: EventoAgenda], calendario: Calendar) -> some View {
        let letras = Calendario.letras(calendario: calendario)
        let mes = calendario.component(.month, from: dia)
        return VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Array(letras.enumerated()), id: \.offset) { _, letra in
                    Text(verbatim: letra).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .frame(height: 14)
            ForEach(0..<(dias.count / 7), id: \.self) { semana in
                HStack(spacing: 2) {
                    ForEach(dias[(semana * 7)..<(semana * 7 + 7)], id: \.self) { d in
                        Button { escolher(d) } label: {
                            VStack(spacing: 1) {
                                numero(d, calendario: calendario)
                                ponto(pontos[d])
                            }
                            .opacity(calendario.component(.month, from: d) == mes ? 1 : 0.4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(selecao(d == dia))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: Geometria.alturaDaFileiraDoMes)
            }
        }
    }

    private func numero(_ d: Date, calendario: Calendar) -> some View {
        let hoje = calendario.isDateInToday(d)
        return Text(verbatim: "\(calendario.component(.day, from: d))")
            .font(.caption.weight(hoje ? .bold : .regular)).monospacedDigit()
            .foregroundStyle(hoje ? Color.red : Color.primary)
    }

    /// O ponto do dia com evento, na cor do calendário do primeiro; sem evento, o espaço dele, para nada pular.
    private func ponto(_ evento: EventoAgenda?) -> some View {
        Circle().fill(corDoCalendario(evento)).frame(width: 4, height: 4).opacity(evento == nil ? 0 : 1)
    }

    private func selecao(_ escolhido: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(escolhido ? 0.16 : 0))
    }

    private func escolher(_ d: Date) {
        withAnimation(Movimento.ou(Movimento.conteudo)) {
            estado.diaEscolhido = d
            agenda.mostrar(Calendario.intervalo(de: d, calendario: .current))
        }
    }

    /// Todos os eventos do dia, sem rolagem: até `maximoDoDia` linhas, a última vira "mais k".
    private func lista(_ eventos: [EventoAgenda]) -> some View {
        let visiveis = Calendario.visiveis(eventos.count, maximo: Geometria.maximoDoDia)
        return VStack(alignment: .leading, spacing: Geometria.espacoLinha) {
            if eventos.isEmpty {
                Label("Nada neste dia", systemImage: "calendar")
                    .foregroundStyle(.secondary)
                    .frame(height: Geometria.alturaLinha)
            }
            ForEach(eventos.prefix(visiveis)) { evento in
                HStack(spacing: 10) {
                    Capsule().fill(corDoCalendario(evento)).frame(width: 3, height: 22)
                    Text(verbatim: AbaHoje.horario(evento))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .frame(minWidth: 84, alignment: .leading)
                        .fixedSize()
                    // verbatim: o título vem do convite de qualquer pessoa.
                    Text(verbatim: evento.titulo).font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .frame(height: Geometria.alturaLinha)
            }
            if eventos.count > visiveis {
                Text(String(localized: "mais \(eventos.count - visiveis)"))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: Geometria.alturaLinha)
                    .padding(.leading, 13)
            }
        }
        .font(.callout)
        .padding(.horizontal, 4)
    }
}
