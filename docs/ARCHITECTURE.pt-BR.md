# Arquitetura

*[Read in English](ARCHITECTURE.md)*

O Kizami é um binário só. Aberto sem argumentos, é o app da barra de menus que desenha a ilha. Com argumentos (`Kizami enviar …`, `Kizami claude`), é a linha de comando que fala com o app aberto e sai.

## O fluxo

```
fontes ──► Mural ──► IlhaView (uma por monitor, dentro de uma Janela)
   │                    ▲
   └── estado próprio ──┘   (tocando agora, sessões, hoje, interesses, apps, Kanji)
```

- **Fontes** produzem atividades ou o próprio estado observável:
  - as atividades que outros apps e scripts mandam (`Correio`);
  - as sessões do Claude Code (`Claude`);
  - os lembretes da agenda (`Agenda`);
  - os lembretes dos interesses e o placar ao vivo (`Interesses`, `Placar`);
  - o aviso de chuva (`Tempo`) e o fim do timer (`Cronometro`);
  - a CI e as revisões do GitHub (`GitHub`) e os downloads em andamento (`Downloads`);
  - a bateria e os emblemas do Dock (`Mac`);
  - os avisos dos atalhos (`Atalhos`, `KanjiAba`).
- **`Mural`** guarda as atividades:
  - no máximo 8, ordenadas pela prioridade e depois pela chegada (`Mural.antes`);
  - o prazo de cada uma, e a pilha de até 3 avisos que fazem a ilha descer por alguns segundos;
  - as ações de clique das fontes do próprio Kizami.
- **`IlhaView`** desenha uma ilha com tudo isso. A **`Janela`** é o `NSPanel` de um monitor: consulta o cursor para abrir e fechar a ilha, deixa os cliques passarem enquanto ela está fechada e a esconde no monitor em tela cheia.
- **`Kizami`** (em `KizamiApp.swift`) é a raiz de composição: cria as fontes uma vez e uma `Janela` por monitor, recriadas quando os monitores mudam.

## O protocolo

Notificações distribuídas com o nome `io.github.henriquebap.kizami.<ação>`, o conteúdo em `object` e `deliverImmediately: true`:

| Ação | Objeto |
|---|---|
| `enviar` | JSON da atividade: `id`, `titulo`, `detalhe?`, `simbolo?`, `cor?`, `expira?`, `prioridade?` |
| `remover` | o id |
| `limpar` | nada |
| `claude` | `{id, pasta, evento, app}`, vindo do `Kizami claude` (hooks do Claude Code, [CLAUDE-HOOKS.md](CLAUDE-HOOKS.md)) |

Qualquer processo do Mac pode postar, então tudo o que chega é dado:
- validado por `Atividade.validar`: tamanho limitado, sem caracteres invisíveis nem de direção, só cores e prioridades conhecidas, só SF Symbols que existem;
- mostrado com `Text(verbatim:)`;
- nunca aberto nem executado. Ação de clique só existe para as fontes do próprio Kizami.

## As formas da ilha

As escolhas da pessoa (`Personalizacao`: abas, seções do Início, a ordem das asas) são lidas onde cada decisão já mora (`Cabecalho`, `secoesAtuais`, `asaAtual`), nunca como `if` espalhado pelas views.

A `Geometria` é pura. Ela é testada com medidas de telas reais e decide todos os tamanhos:

| Estado | Forma |
|---|---|
| repouso | uma pílula um pouco maior que o notch |
| fechada (`compacta`) | asas em volta do notch: até 3 ícones, a contagem do timer ou o placar ao vivo (`asaAtual` escolhe um) |
| aviso (`aviso`) | até 3 linhas abaixo do notch |
| aberta (`aberta`) | o cabeçalho (abas e ⚙︎) e as seções que têm o que mostrar |

A área do hover e a forma desenhada vêm sempre das mesmas funções (`tamanhoFechado`, `tamanhoAberto`), então as duas não se desencontram.

## Tela cheia

O macOS desenha um painel no nível da ilha até num espaço de tela cheia, então o próprio Kizami esconde a ilha. O sinal é que um monitor em tela cheia perde as janelas do papel de parede e da mesa do Finder, que o `CGWindowListCopyWindowInfo` lista sem permissão nenhuma. A conferência roda a cada troca de espaço, troca de monitor e quando o Mac acorda.

## Permissões e rede

| O quê | Pede |
|---|---|
| Capa e botões da música | Automação (Music, Spotify) |
| Próximo evento | Calendários |
| Emblemas do Dock, aba Atalhos, aba Kanji | Acessibilidade |
| Tempo | rede: Open-Meteo |
| Interesses, placar ao vivo | rede: o JSON público da ESPN e os links ICS que a pessoa cola |
| Play/pause do navegador, colar dos Copiados | Acessibilidade |
| Espelho da câmera | Câmera |
| Downloads | a pasta Downloads |
| GitHub | a CLI `gh` que a pessoa logou (o Kizami nunca vê o token) |

Cada uma é opcional, e sem ela o resto continua funcionando. As chamadas de rede usam:
- só HTTPS, com timeout e teto de tamanho;
- redirecionamento conferido antes de ser seguido;
- uma sessão efêmera.

Conteúdo nunca vai para o log: títulos, nomes de pasta, a cidade, times, nomes de app e números de emblema. Só contagens e tempos.

O texto copiado fica só na memória. Copiados, Downloads, GitHub e o urgente por cima da tela cheia ficam desligados até a pessoa ligar.

## Energia

O SwiftUI desenha a ilha na CPU, e cada quadro de animação redesenha a ilha inteira (texto, capa, contorno). Por isso:
- nada anima sem parar com a ilha fechada: um enfeite contínuo (o equalizador) é uma layer do Core Animation, que roda no servidor de janelas;
- o que muda todo segundo (o timer nas asas) muda sem animação;
- uma fonte só escreve numa propriedade observada quando algo na tela muda (`SessoesClaude.mesmasNaTela`).

- o que vem de fora só é lido enquanto está na tela: a posição do player uma vez por segundo só com a música expandida (`Janela.acertarProgresso`), o mês visível só com a agenda expandida (`Agenda.mostrar`);
- um aviso importante só passa na frente nas asas nos primeiros 2 minutos, virado por uma única Task agendada (`Mural.importante`), sem consulta repetida.

O vidro (`Visual.swift`: `.vidro`, `Movimento`) é desenhado pelo servidor de janelas, e as molas ficam num lugar só. Um item expandido (`EstadoIlha.expandido`, `expansaoAtual`) entra em `tamanhoAberto`, então o desenho e a área do hover continuam vindo da mesma função.

Para medir: `top -l 7 -s 10 -pid $(pgrep -x Kizami) -stats pid,cpu,idlew,power` e `sample`. Com música e timer ligados: ~0,7% de CPU.

## Testes

O `make teste` junta `Tests/*.swift` com as partes puras das fontes num executável que imprime `ok` ou `FALHA`. As partes puras são:
- geometria, prioridade, validação e linha de comando;
- janelas dos lembretes, leitura da ESPN e do ICS;
- a regra da tela cheia, as decisões da bateria e dos emblemas, a leitura dos atalhos e das skills do Kanji.

O que depende do Mac de verdade é conferido no app instalado, pelo log:
- microfone, câmera, Dock, EventKit;
- a lista de janelas.

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "io.github.henriquebap.kizami"' --style compact --info
```
