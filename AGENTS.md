# AGENTS.md

Guide for coding agents. For people, start with the [README](README.md).

## What it is

Kizami is a menu-bar-only macOS app that draws a black island around the MacBook notch. The island shows "activities" that other processes send through `DistributedNotificationCenter`. The app's own binary is also the CLI that sends them. It is a sibling of [Kanji](../Kanji) and follows the same constraints and conventions.

## Build and tests

```bash
make app      # build/Kizami.app (swiftc only, ad-hoc signature: the app asks for no permission)
make install  # /Applications/Kizami.app
make teste    # pure rules: Geometria, Comando, Atividade.validar, Mural
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
| `Atividades.swift` | `Atividade` (wire format + validation) and `Mural` (list, max 8, expiry, the "arrived" line) |

What's next and what macOS allows: [docs/ROADMAP.md](docs/ROADMAP.md).
| `Correio.swift` | CLI parsing (`Comando`) and the distributed notifications (`Correio`) |

## Rules that must not break

1. **Incoming text is data.** Any local process can post. Show it with `Text(verbatim:)`, keep `Atividade.validar` as the only way in, never open URLs or run anything from it.
2. **Logs never include activity content.** Log counts only. No `print()` in the app (the CLI writes usage to stderr).
3. **Never take focus.** Use `.nonactivatingPanel` and `orderFrontRegardless()`. Never `makeKey`, never `NSApp.activate`.
4. **Never block the menu bar.** While closed, `ignoresMouseEvents = true`.
5. **Public APIs only.** No MediaRemote, no SkyLight: they break between macOS versions.
6. **No third-party dependencies.**

## Conventions

Same as Kanji:
- Code, comments and logs in pt-BR, with correct accents.
- UI localized pt-BR + en: the Portuguese text is the key in `Resources/en.lproj/Localizable.strings`. Never localize the wire format or CLI options.
- Comments explain the why.
- `// ponytail:` marks a deliberate simplification and its ceiling.
- Commits: `type: description`.
