# Architecture

*[Leia em português](ARCHITECTURE.pt-BR.md)*

Kizami is one binary: launched without arguments it is the menu-bar app that draws the island; with arguments (`Kizami enviar …`, `Kizami claude`) it is the command line that talks to the running app and exits.

## The flow

```
sources ──► Mural ──► IlhaView (one per display, inside a Janela)
   │                     ▲
   └──── own state ──────┘   (now playing, sessions, today, interests, apps, Kanji)
```

- **Sources** produce activities or their own observable state:
  - activities sent by other apps and scripts (`Correio`);
  - Claude Code sessions (`Claude`);
  - calendar reminders (`Agenda`);
  - interests reminders and the live score (`Interesses`, `Placar`);
  - the rain alert (`Tempo`) and the timer's end (`Cronometro`);
  - battery and Dock badges (`Mac`);
  - the shortcut prompts (`Atalhos`, `KanjiAba`).
- **`Mural`** keeps the activities:
  - at most 8, sorted by priority and then arrival (`Mural.antes`);
  - expiry, and the stack of up to 3 notices that drop the island for a few seconds;
  - the click actions of Kizami's own sources.
- **`IlhaView`** draws one island from all of it. **`Janela`** is one display's `NSPanel`: it polls the cursor to open and close the island, lets clicks through while closed, and hides on a full-screen display.
- **`Kizami`** (in `KizamiApp.swift`) is the composition root: it creates the sources once and one `Janela` per display, rebuilt when displays change.

## The protocol

Distributed notifications, named `io.github.henriquebap.kizami.<action>`, with the payload in `object` and `deliverImmediately: true`:

| Action | Object |
|---|---|
| `enviar` | Activity JSON: `id`, `titulo`, `detalhe?`, `simbolo?`, `cor?`, `expira?`, `prioridade?` |
| `remover` | the id |
| `limpar` | nothing |
| `claude` | `{id, pasta, evento, app}` from `Kizami claude` (Claude Code hooks, [CLAUDE-HOOKS.md](CLAUDE-HOOKS.md)) |

Any local process can post, so everything that arrives is data:
- validated by `Atividade.validar`: length caps, no invisible or direction characters, known colors and priorities, existing SF Symbols;
- shown with `Text(verbatim:)`;
- never opened or run. Click actions exist only for Kizami's own sources.

## The island's shapes

`Geometria` is pure. It is tested with real screen measurements and decides every size:

| State | Shape |
|---|---|
| resting | a pill slightly larger than the notch |
| closed (`compacta`) | wings around the notch: up to 3 icons, the timer's countdown or the live score (`asaAtual` picks one) |
| notice (`aviso`) | up to 3 lines below the notch |
| open (`aberta`) | the header (tabs and ⚙︎), then the sections that have something to show |

The hover area and the drawn shape always come from the same functions (`tamanhoFechado`, `tamanhoAberto`), so they can't drift apart.

## Full screen

macOS draws a panel at the island's level even on a full-screen Space, so Kizami hides the island itself. The signal is that a display in full screen loses the wallpaper and Finder desktop windows, which `CGWindowListCopyWindowInfo` lists with no permission. The check runs on every Space change, display change and wake.

## Permissions and network

| What | Needs |
|---|---|
| Artwork and media buttons | Automation (Music, Spotify) |
| Next event | Calendars |
| Dock badges, Shortcuts tab, Kanji tab | Accessibility |
| Weather | network: Open-Meteo |
| Interests, live score | network: ESPN's public JSON, plus the ICS links the person pastes |
| Browser play/pause | Accessibility |

Each one is optional, and the rest keeps working without it. Network calls use:
- HTTPS only, with a timeout and a size cap;
- redirects checked before they are followed;
- an ephemeral session.

Content never goes to the log: titles, folder names, the city, teams, app names and badge counts. Only counts and timings do.

## Tests

`make teste` builds `Tests/*.swift` with the pure parts of the sources into one executable that prints `ok` / `FALHA`. The pure parts are:
- geometry, priority, validation and the command line;
- reminder windows, ESPN and ICS parsing;
- the full-screen rule, the battery and badge decisions, Kanji's shortcut and skill parsing.

The parts that need the real Mac are checked in the installed app, through the log:
- microphone, camera, Dock, EventKit;
- the window list.

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "io.github.henriquebap.kizami"' --style compact --info
```
