# Kizami

*[Read in English](README.md)*

Uma pequena ilha em volta do notch do MacBook que mostra o que outros apps e scripts estão fazendo: um build que terminou, uma transcrição rodando, um agente de IA esperando por você. Passe o mouse para ver a lista. O Kizami nunca rouba o foco do app em que você está.

*Kizami* (刻み) é "entalhe" em japonês, o nome do notch. Vem de *kizamu*, que é entalhar e também marcar o tempo que passa.

| Fechada | Chegou uma atividade | Com o mouse em cima |
|---|---|---|
| ![fechada](docs/fechada.png) | ![aviso](docs/aviso.png) | ![aberta](docs/aberta.png) |

Gratuito e open source (Apache 2.0). Não usa API privada nem pede permissão. Não tem dependências de terceiros.

## Compilar

Só precisa das Command Line Tools (`xcode-select --install`), sem Xcode.

```bash
make app       # build/Kizami.app
make install   # copia para /Applications e abre
make teste     # testes das regras puras
```

## Enviar uma atividade

O próprio binário do app também é a linha de comando:

```bash
K=/Applications/Kizami.app/Contents/MacOS/Kizami
$K enviar --titulo "Build pronto" --detalhe "12 s" --simbolo hammer --cor verde
$K enviar --titulo "Transcrevendo" --simbolo waveform --cor vermelho --id rec --expira 0
$K remover --id rec
$K limpar
```

- `--simbolo`: o nome de qualquer SF Symbol. Um nome que não existe vira `bell.fill`.
- `--cor`: uma de `vermelho`, `laranja`, `amarelo`, `verde`, `azul`, `roxo`, `rosa`, `cinza`.
- `--expira`: segundos até a atividade sumir (padrão: 10). `0` deixa na ilha até o `remover`.
- `--id`: enviar de novo com o mesmo id substitui a atividade.

De outro app, poste uma notificação distribuída com o nome `io.github.henriquebap.kizami.enviar`. O JSON da atividade vai em `object`: `{"id", "titulo", "detalhe"?, "simbolo"?, "cor"?, "expira"?}`. Passe `deliverImmediately: true`: o Kizami nunca é o app ativo, e sem esse parâmetro o macOS pode segurar a notificação.

**O que chega é dado, nunca comando.** Qualquer processo do Mac pode enviar. O Kizami só exibe: tira os caracteres invisíveis e de direção, limita o tamanho e nunca interpreta Markdown. *Limpar a ilha*, no item do Kizami na barra de menus, tira tudo.

## Comportamento

- **Notch:** na tela com notch, a ilha abraça o notch e abre quando o cursor toca o próprio notch, nunca os menus ao lado. Em tela sem notch, a ilha é só as duas "asas", sob a barra de menus.
- **Monitores:** uma ilha em cada monitor, para você ver na tela em que está trabalhando. Elas são recriadas quando os monitores mudam.
- **Atividade nova:** a ilha desce uma linha abaixo do notch com o título por alguns segundos e depois volta a fechar.
- **Ao abrir:** mostra "Kizami está rodando", e o item na barra de menus diz quantas atividades há na ilha.
- **Tela cheia:** a ilha aparece por cima de apps em tela cheia.
- **Sem atividade:** a ilha encolhe de volta para dentro do notch.
- **Cliques:** fechada, ela deixa os cliques passarem para a barra de menus.

## Licença

[Apache 2.0](LICENSE). O nome **Kizami** e o ícone não fazem parte da licença (veja o [NOTICE](NOTICE)).
