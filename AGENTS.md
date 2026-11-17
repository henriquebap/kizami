# AGENTS.md

Guide for coding agents. For people, start with the [README](README.md). For the design, see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## What it is

Kizami is a menu-bar-only macOS app that draws a black island around the MacBook notch. The island shows "activities" that other processes send through `DistributedNotificationCenter`. The app's own binary is also the CLI that sends them. It is a sibling of [Kanji](../Kanji) and follows the same constraints and conventions.

## Build and tests

```bash
make app      # build/Kizami.app (swiftc only; signed with the local "Kanji Dev" certificate when present, so permissions survive rebuilds)
make install  # /Applications/Kizami.app
make teste    # pure rules: Geometria, Comando, Atividade, Som, Agenda, Tempo, Claude, Mac, Interesses, Placar, Cronometro, Copiados, Espelho, Downloads, GitHub, Personalizacao, AtalhosApple
```

**Constraints:**
- Built with `swiftc` from the Command Line Tools only: no Xcode, no SwiftPM, no `@State` / `#Preview` / `@Generable` macros. View state lives in `@MainActor @Observable` classes.
- Swift 6 strict concurrency, target `arm64-apple-macosx27.0`.
- Tests are a plain executable that prints `ok`/`FALHA` (`conferir(nome, obtido, esperado)` in `Tests/KizamiTeste.swift`). To test a new file, add it to the `teste` line of the `Makefile`.

**Verify in the real app:**
```bash
make install && /Applications/Kizami.app/Contents/MacOS/Kizami enviar --titulo teste --expira 0
/usr/bin/log show --last 5m --predicate 'subsystem == "io.github.henriquebap.kizami"' --style compact --info
```

## Code map

| File | Responsibility |
|---|---|
| `KizamiApp.swift` | Entry point (app or CLI), menu bar item, composition (`Kizami.shared`: one `Janela` per display, rebuilt on screen changes) |
| `Geometria.swift` | Pure: notch size and the sizes of each state (closed, arrived, open) from `NSScreen` measurements |
| `Janela.swift` | One display's `NSPanel`, hover polling, `ignoresMouseEvents` |
| `IlhaView.swift` | The notch-shaped outline (`FormaIlha`), the states and their spring animations |
| `Bandeja.swift` | The file tray: URLs in memory (max 20), dedupe, prune missing files |
| `Arrasto.swift` | Global mouse monitors + the drag pasteboard: notices a file drag in any app so the closed island opens and accepts the drop |
| `Atividades.swift` | `Atividade` (wire format + validation) and `Mural` (list, max 8, expiry, the "arrived" line) |
| `Som.swift` | Now playing: Core Audio process list (who has audio output open), media-app allowlist, Music/Spotify notifications, debounce |
| `Player.swift` | Music and Spotify through `osascript`: media commands (`Controle`), artwork (`Capa`: Music bytes to a temp file, Spotify URL from `*.scdn.co`), the runner with a timeout (`AppleScript`) |
| `Correio.swift` | CLI parsing (`Comando`, including `Kizami claude` for Claude Code hooks) and the distributed notifications (`Correio`) |
| `Claude.swift`, `ClaudeView.swift` | Claude Code sessions: hook events → session states, expiry, the "needs you" alert, the open-island section |
| `Agenda.swift`, `AgendaView.swift` | Calendar (EventKit): next event, meeting-link allowlist, 15-min / starting reminders, the "Today" chip |
| `Tempo.swift`, `TempoView.swift` | Weather from Open-Meteo for the city in Settings: fetch + validation, WMO code → symbol, the "Today" chip |
| `Interesses.swift`, `InteressesView.swift` | Interests: ESPN schedules (teams, F1) and ICS feeds the person adds, the week / day-before / 1-hour reminders, the open-island row and its Settings section |
| `Placar.swift` | Live score: ESPN scoreboard parsing and validation, when to poll, the live game in the Interests row |
| `Cronometro.swift`, `CronometroView.swift` | Timer / pomodoro: the countdown, the focus → break cycle, the Timer tab and the countdown in the closed wings |
| `Personalizacao.swift`, `PersonalizacaoView.swift` | The person's choices: tabs and order, hidden Home sections, the order of the wings (`Aba`, `Asa`); the Settings section |
| `AtalhosApple.swift`, `AtalhosAppleView.swift` | Apple Shortcuts chosen in Settings, run with `/usr/bin/shortcuts run -- <name>`; the row in the Shortcuts tab |
| `Copiados.swift`, `CopiadosView.swift` | Clipboard history (opt-in, memory only, password/key filter), the Copied tab, paste with ⌘V |
| `GitHub.swift`, `GitHubView.swift` | CI failed / review requested through the logged-in `gh` (opt-in, read only), its Settings section |
| `Downloads.swift`, `DownloadsView.swift` | Downloads in progress from `~/Downloads` partial files (opt-in), its Settings section |
| `Espelho.swift`, `EspelhoView.swift` | Camera mirror (video only), opened from the Shortcuts tab, off when the island closes |
| `Mac.swift`, `MacView.swift` | Mic and camera in use, battery, Dock badges (opt-in, Accessibility): the privacy dots, the open-island row, its Settings section |
| `Atalhos.swift` | The Shortcuts tab: system shortcuts sent as key events (screenshots, emoji, lock) or opened as apps (Mission Control); the media play/pause key for browsers (`TeclaDeMidia`) |
| `Kanji.swift`, `KanjiAba.swift` | The Kanji tab: Kanji's global shortcuts read from its defaults, skill headers from `~/Library/Application Support/Kanji/Skills`, sent as key events |
| `AjustesView.swift` | The Settings window (city, calendar access, interests, apps and Mac, Claude hooks pointer) |

What's next and what macOS allows: [docs/ROADMAP.md](docs/ROADMAP.md).

## Rules that must not break

1. **Incoming text is data.** Any local process can post. Show it with `Text(verbatim:)`, keep `Atividade.validar` as the only way in, never open URLs or run anything from it. Click actions (`Mural.receber(_:aoAbrir:)`) exist only for Kizami's own sources. Links opened: a meeting link from the user's own calendar (only if `EventoAgenda.aceito` passes: https + allowlisted host) an ESPN game page (https on `www.espn.com`) and a GitHub PR page (`GitHub.link`: https, host exactly `github.com`, no user or port), all only on the user's click.
2. **Logs never include activity content.** Log counts only. No `print()` in the app (the CLI writes usage to stderr).
3. **Never take focus.** Use `.nonactivatingPanel` and `orderFrontRegardless()`. Never `makeKey`, never `NSApp.activate`. The one exception is the Settings window the person asked for (`Kizami.abrirAjustes`).
4. **Never block the menu bar.** While closed, `ignoresMouseEvents = true`.
5. **Public APIs only.** No MediaRemote, no SkyLight: they break between macOS versions.
6. **Permissions stay optional.** Automation (artwork, media buttons), Calendars (next event) and Accessibility (Dock badges, off by default; the Shortcuts and Kanji tabs, browser play/pause and pasting from Copied, asked on first use), Camera (the mirror, asked when opened) and Files and Folders (Downloads, opt-in). Denied, everything else keeps working. Track titles, event titles, session folders, the city, followed teams, app names and badge counts are content: never in logs.
7. **No third-party dependencies.**
8. **Network only to named services that need no key**, over HTTPS with a timeout, a size cap and the redirect target checked: today Open-Meteo and ESPN's public JSON (`site.api.espn.com`), plus ICS feeds whose link the person pastes in Settings. A new service is a decision written in the ROADMAP. GitHub goes through the person's own `gh` CLI (fixed arguments, timeout, output cap), never a token in Kizami.
9. **Opt-in for what reads more of the Mac:** Copied (clipboard, memory only), Downloads, GitHub and urgent-over-full-screen start off. Only Kizami's own sources (the ones with a click action) may show over full screen.

## Conventions

Same as Kanji:
- Code, comments and logs in pt-BR, with correct accents.
- Docs are English-first; README and ARCHITECTURE have pt-BR copies (`README.pt-BR.md`, `docs/ARCHITECTURE.pt-BR.md`). Change both.
- UI localized pt-BR + en: the Portuguese text is the key in `Resources/en.lproj/Localizable.strings`. Never localize the wire format or CLI options.
- Comments explain the why.
- `// ponytail:` marks a deliberate simplification and its ceiling.
- Commits: `type: description`.
