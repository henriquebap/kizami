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

- The island hides on a display that is in full screen (video, game, presentation): the panel no longer joins full-screen Spaces.

## Plan from v0.5

Kizami is the more flexible sibling of Kanji: it may call **named network services that need no key** (Open-Meteo, ESPN's public JSON, ICS feeds the person adds) and ask for **one opt-in permission per feature**. What stays: no third-party dependencies, public APIs only, content (event titles, session names, scores) never in logs.

### Shared groundwork (built with the first phase that needs it)

| Piece | What | Why |
|---|---|---|
| **Settings window** (done: city) | City, interests, one toggle per module | |
| **Reminder schedule** (pure) | From an event's start: "this week", "tomorrow", "in 1 hour", "in 15 min" → activities in the `Mural` | Calendar and interests use the same rule; tested like `Geometria`. |
| **Who owns the closed wings** (pure) | Music, a meeting in 5 min, a Claude session waiting: one wins the closed island | A product decision, written as a small tested function. |
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

### v0.7: Interests (the "external calendar")

Events the person follows but doesn't keep in their calendar (Buffalo Bills, F1, a football club):

| Source | How | Notes |
|---|---|---|
| Teams and leagues | ESPN's public JSON (`site.api.espn.com/apis/site/v2/sports/{sport}/{league}/teams/{team}/schedule`, F1 at `racing/f1/scoreboard`), no key | Undocumented and could change without notice; one source file, easy to swap. Covers NFL, NBA, F1 and the Brazilian league. |
| Anything with a feed | ICS URL pasted in Settings; a small `VEVENT` reader (`DTSTART`, `SUMMARY`) | No dependency. |
| Reminders | The shared schedule: the week's list, the day before, 1 hour before | |
| Later: live score | Poll the ESPN scoreboard every minute only while a followed game is on | |

### v0.8: Apps and the Mac

| What | How | Permission |
|---|---|---|
| Unread counts (WhatsApp 3, Mail 12) | The Dock's badges through Accessibility | Accessibility |
| Which app is using the mic | Core Audio `kAudioProcessPropertyIsRunningInput`, the same process list as "now playing" | none |
| Camera in use | CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` (that it is, not which app) | none |
| Battery low / charging | IOKit `IOPSNotificationCreateRunLoopSource` | none |
| Kanji is transcribing (done on Kanji's side: id `kanji-transcricao`) | Kanji posts `io.github.henriquebap.kizami.enviar` | none |
| Timer | Kizami's own state, set from the open island | none |
| Media keys for browsers (YouTube) | Post the system media-key events | Accessibility |

## Not possible with public APIs

- **Other apps' notification text** (WhatsApp, Slack, Messages). macOS has no API to read another app's notifications, and macOS 26.3 moved the Notification Center data to a protected location (CVE-2026-20648). Reading the banners through Accessibility is fragile. What is possible: the unread *count* from the Dock badge (v0.8), and any app or script that wants to show up can send an activity to Kizami.
- **Lock screen island.** Needs the private SkyLight framework.
- **Replacing the volume / brightness HUD.** Needs to intercept media keys (Accessibility) and breaks between macOS versions.
