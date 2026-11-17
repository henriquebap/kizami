# Roadmap

Kizami stays on public APIs, so every feature below says what macOS allows and what it costs in permissions. Status as of November 2026, macOS 27; items marked *to validate* still need a test on the current macOS.

## v0.1 (done)

- One island per display, hugging the notch (or the top center on displays without one).
- Activities from other apps and scripts (`Kizami enviar`, distributed notifications).
- Closed → "arrived" line → open list on hover, with spring animations.

## v0.2 (done)

- File tray: drop files on the notch, drag them out, AirDrop them. In memory only.

## v0.3 (done)

- The island is always visible, resting around the notch.
- Now playing: which media app is playing (Core Audio process list, no permission), title and artist from Music and Spotify notifications, artwork through AppleScript (Automation).

## v0.4 (done)

- Previous / play-pause / next for Music and Spotify on the open island; a paused player stays on the island for up to 15 minutes.

## v0.4.1 (done)

- The island hides on a display that is in full screen (video, game, presentation). Dropping `.fullScreenAuxiliary` wasn't enough: at the island's window level macOS still draws it on a full-screen Space (seen with YouTube in Chrome). The working signal is that macOS takes the wallpaper and the Finder desktop windows off a display in full screen; Kizami checks the window list on every Space change.

## Plan from v0.5

Kizami is the more flexible sibling of Kanji: it may call **named network services that need no key** (Open-Meteo, ESPN's public JSON, ICS feeds the person adds) and ask for **one opt-in permission per feature**. What stays: no third-party dependencies, public APIs only, content (event titles, session names, scores) never in logs.

### Shared groundwork (built with the first phase that needs it)

| Piece | What | Why |
|---|---|---|
| **Settings window** (done: city) | City, interests, one toggle per module | |
| **Reminder schedule** (pure) | From an event's start: "this week", "tomorrow", "in 1 hour", "in 15 min" → activities in the `Mural` | Calendar and interests use the same rule; tested like `Geometria`. |
| **Priority queue** (done) | Activities carry `prioridade` (`baixa`, `normal`, `alta`, `urgente`). The island sorts by it, then by arrival; full, it drops the least important. Up to three notices drop together, and the closed wings show up to three icons. `baixa` joins without dropping the island. | `Mural.antes` is the whole rule. Activities still beat music in the closed wings. |
| **Urgent over full screen** | Optional: a meeting about to start or a Claude permission prompt still shows on a full-screen display | Needs a second panel that does join full-screen Spaces; off by default. |

### v0.5: Claude sessions (done)

| What | How | Permission |
|---|---|---|
| Running sessions, each with its folder and state (working, needs you, done) | Claude Code hooks (`SessionStart`, `UserPromptSubmit`, `Notification` with `permission_prompt` / `idle_prompt`, `Stop`, `SessionEnd`) run `Kizami claude`, which reads the hook JSON from stdin and posts it | none |
| "Needs you" alert, with the closed wings pulsing | `Notification` hook | none |
| Click a session to jump to it | Activate the app that runs it; a deep link to a desktop-app session is *to validate* | none |

Only `session_id`, the folder name and the state cross over; never the prompt or the reply. Answering a permission prompt from the island is not possible: Claude Code has no public way in.

### v0.6: Today (calendar and weather) (done)

| What | How | Permission |
|---|---|---|
| Next event on the open island; alert 15 min before; "Join" button when the event has a Meet / Zoom / Teams link | EventKit | Calendars (full access) |
| Temperature and today's forecast | Open-Meteo (`api.open-meteo.com`, no key), city typed in Settings (Open-Meteo geocoding), refreshed every 30 min | none (network) |

WeatherKit needs a paid developer account, and Core Location would ask for location for a city the person can type once.

### v0.7: Interests (the "external calendar") (done)

Events the person follows but doesn't keep in their calendar (Buffalo Bills, F1, a football club):

| Source | How | Notes |
|---|---|---|
| Teams and leagues | ESPN's public JSON (`site.api.espn.com/apis/site/v2/sports/{sport}/{league}/teams/{team}/schedule`, F1 at `racing/f1/scoreboard`), no key | Undocumented and could change without notice; one source file, easy to swap. Covers NFL, NBA, F1 and the Brazilian league. |
| Anything with a feed | ICS URL pasted in Settings; a small `VEVENT` reader (`DTSTART`, `SUMMARY`) | No dependency. |
| Reminders | The shared schedule: the week's list, the day before, 1 hour before | |
| Live score (v0.10) | The ESPN scoreboard (`?dates=` the game's day) every minute, only in the 5 h after a followed game starts | One game at a time; not F1 |

### v0.8: Apps and the Mac (done; timer and browser media keys in v0.10)

| What | How | Permission |
|---|---|---|
| Unread counts (WhatsApp 3, Mail 12) | The Dock's badges through Accessibility | Accessibility |
| Which app is using the mic | Core Audio `kAudioProcessPropertyIsRunningInput`, the same process list as "now playing" | none |
| Camera in use | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` (that it is, not which app) | none |
| Battery low / charging | IOKit `IOPSNotificationCreateRunLoopSource` | none |
| Kanji is transcribing (done on Kanji's side: id `kanji-transcricao`) | Kanji posts `io.github.henriquebap.kizami.enviar` | none |
| Timer | Kizami's own state, set from the open island | none |
| Media keys for browsers (YouTube) | Post the system media-key events | Accessibility |

### v0.9: The open island as a menu (done)

- Tabs at the top of the open island: **Home**, **Shortcuts** and **Kanji**, plus a ⚙︎ that opens Settings.
- **Shortcuts:** the Mac's shortcuts in one click, with the keys written under each one (screenshots, Mission Control, emoji, lock).
- **Kanji:** dictate, transcribe the Mac's audio, open Kanji, and one button per Kanji skill. They are Kanji's own global shortcuts, read from its settings and sent as key events.
- **Click an activity to open it:** the Claude session's app, the game's ESPN page, the meeting, the Dock app. Only Kizami's own sources get an action; activities from outside only show.
- **Clear:** a Clear button for every activity, and a ✕ on the row under the cursor.
- **Interests side by side:** the next event of each followed source, up to three.

### v0.10: The first ideas (done)

- **Live score** in the closed wings and the Interests row; "Game over" notice at the end.
- **Rain alert:** Open-Meteo `minutely_15` precipitation, refreshed every 15 min; one notice per rain episode.
- **Timer / pomodoro:** a Timer tab, the countdown in the closed wings, the focus → break cycle by clicking the notice. No sound yet.
- **Today tab:** the rest of the day's calendar.
- **Browser play/pause:** the system media key, for players without AppleScript.

### v0.11: The second batch (done)

- **Copied:** clipboard history in memory only (10 texts, password-manager types and key-like text filtered), click to paste. Off by default.
- **GitHub:** CI failed / review requested on your PRs through the logged-in `gh` (one GraphQL query every 5 min, read only). Not a new service Kizami talks to: `gh` does. Off by default.
- **Downloads:** `.crdownload` / `.download` / `.part` in `~/Downloads`, size or percentage, then done with a click to reveal. Off by default.
- **Camera mirror:** `AVCaptureVideoPreviewLayer` in the open island from the Shortcuts tab; video only, off when the island closes.
- **Urgent over full screen:** the same panel, kept on screen only for an urgent notice from Kizami's own sources. Off by default.

### v0.12: Personalization (done)

- Tabs on/off and their order; the island opens on the first. Home always stays.
- Home sections can be hidden; a hidden section leaves the island and the height math together (`secoesAtuais`).
- The order of the closed wings (`Personalizacao.asa`); important notices always first.
- Timer: focus, break and up to 3 free timers in Settings.
- Apple Shortcuts: up to 6 chosen shortcuts as buttons in the Shortcuts tab, run with `/usr/bin/shortcuts run -- <name>`.

### v0.13: Daily use (done)

- Open at login with `SMAppService.mainApp` (Settings › General).
- The meeting countdown in the closed wings (`Asa.reuniao`, first by default; a saved order gets it at its default place).
- The timer saved in `timer.estado` and restored on launch; an end missed by less than 1 h still notifies.
- Images in Copied (PNG/TIFF, memory only, 10 MB each, 50 MB in all).
- Still open: new screenshots in `docs/` (they need the Screen Recording permission).

### v0.14: Depth (done)

- Opening the exact Claude session: the hook sends the tab's tty (`ttys003`, validated) and the click selects that tab in Terminal or iTerm2 through AppleScript. VS Code and the Claude app get the app only: their documented links don't pick the right window.
- Two live games at once (the wings alternate every 8 s) and the F1 top 3 from ESPN's scoreboard (`competitors[].order`; driver codes from the surname, since there's no abbreviation field).
- Energy: measured with `top` and `sample`, Kizami sat at ~33% CPU with music and a timer on. SwiftUI redraws the whole island on the CPU for every animation frame, so the equalizer moved to Core Animation, the closed timer stopped rolling its digits, and the Claude sessions only redraw on a visible change. Now ~0.7% CPU and ~1.5 wakeups/s.

### v0.15: UI and motion (done)

- **Glass inside a black island.** The island stays black, because it has to merge with the notch, like the Dynamic Island. The chips, cards and buttons inside become Liquid Glass (`GlassEffectContainer`, `glassEffect`). When an item expands, its glass morphs into the expanded shape (`glassEffectID`).
- **Motion.** One set of springs for opening, closing, content and expanding (`Movimento`), instead of one per view. The selected tab is a glass pill that slides between tabs, and the Home sections come in one after another. Reduce Motion is respected. The closed island stays at ~0.3% CPU with the glass.
- **Items that expand in place.** Clicking a chip grows it inside the island; clicking its header collapses it, and closing the island resets it (`EstadoIlha.expandido`).
  - **Calendar:** a week strip with a dot on each day that has events. Clicking a day shows all of its events, and you can switch between Week and Month.
  - **Music:** large artwork, elapsed and remaining time from the player's `player position` and `duration` (Spotify and Music), and a bar you drag to seek. The position is read once a second, and only while the music is expanded.
  - **Lyrics: not now.** Spotify doesn't expose lyrics. Music only has them for tracks that carry them, and an online lyrics service would be a new network service.
- **Claude notice you can dismiss.** The ✕ is always visible. A dismissed notice only comes back when the session changes state. After 2 min the notice leaves the wing and stays only in the list.
- **See-through open island** (Settings › Island › Background): below 100%, the open island turns into glass darkened by that much; closed, it stays black.
- **The date next to the temperature** ("Tue 17 · 24°").
- Not done: the artwork and the meeting dot moving from the closed wing into the open island (`matchedGeometryEffect`).
- To test by hand: iTerm2 may start the shell under `iTermServer`, outside the `.app`; if so, the click finds neither the app nor the tab.

### v0.16

- **Headphones connected** (off by default, Settings › Headphones): when AirPods or other Bluetooth headphones connect, the island shows the name and battery ("L 80% · R 78% · case 55%", or the single battery). The connection comes from IOBluetooth's connect notifications, and the battery from one `system_profiler -json SPBluetoothDataType` run (fixed arguments, timeout, size cap). Asks for Bluetooth. Only listens: never connects, disconnects or touches the audio output.

### Next

Later: Kanji's live mic level (it needs Kanji, which would post a level, never text, on the existing protocol), new screenshots in `docs/`, and focusing a session in VS Code or the Claude app if a link that picks the right window gets documented.

## Ideas (not scheduled)

Ranked by value for daily use against the work it takes.

| Idea | How | Cost |
|---|---|---|
| Kanji: live level of the microphone while dictating | Kanji posts a level (never text) on the existing protocol | medium (both apps) |

## Not possible with public APIs

- **Other apps' notification text** (WhatsApp, Slack, Messages). macOS has no API to read another app's notifications, and macOS 26.3 moved the Notification Center data to a protected location (CVE-2026-20648). Reading the banners through Accessibility is fragile. What is possible: the unread *count* from the Dock badge (v0.8), and any app or script that wants to show up can send an activity to Kizami.
- **Lock screen island.** Needs the private SkyLight framework.
- **Replacing the volume / brightness HUD.** Needs to intercept media keys (Accessibility) and breaks between macOS versions.
