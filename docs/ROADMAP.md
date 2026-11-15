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

## Next candidates

| Feature | How | Permission | Notes |
|---|---|---|---|
| **Media keys for browsers** (YouTube play/pause) | Post the system media-key events | Accessibility | Would also reach any app that handles media keys. |
| **Title of a browser tab** (YouTube) | No public API; the browser's tab title through Accessibility | Accessibility | Fragile. |
| **Mic / camera in use** | CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`, CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` | none | Says *that* they are in use, not *which app*. |
| **Battery / charging** | IOKit `IOPSNotificationCreateRunLoopSource` | none | Plugged in, unplugged, low battery. |
| **Next calendar event** | EventKit | Calendar | |
| **Download finished** | Watch `~/Downloads` (FSEvents) | Downloads folder | |
| **Timer / Pomodoro** | Kizami's own state | none | |

## Not possible with public APIs

- **Other apps' notifications and messages** (WhatsApp, Slack, Messages). macOS has no API to read another app's notifications. The workarounds are reading Notification Center through Accessibility, which is fragile and needs a broad permission, or reading Messages' database, which needs Full Disk Access. The supported path is the other way around: an app or script that wants to show up sends an activity to Kizami.
- **Lock screen island.** Needs the private SkyLight framework.
- **Replacing the volume / brightness HUD.** Needs to intercept media keys (Accessibility) and breaks between macOS versions.
