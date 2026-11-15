# Roadmap

Kizami stays on public APIs, so every feature below says what macOS allows and what it costs in permissions. Status as of November 2026, macOS 27; items marked *to validate* still need a test on the current macOS.

## v0.1 (done)

- One island per display, hugging the notch (or the top center on displays without one).
- Activities from other apps and scripts (`Kizami enviar`, distributed notifications).
- Closed → "arrived" line → open list on hover, with spring animations.

## Next candidates

| Feature | How | Permission | Notes |
|---|---|---|---|
| **File tray** (drop files on the notch, AirDrop them) | Drag and drop onto the panel + `NSSharingService(named: .sendViaAirDrop)` | none | The panel must accept drags while closed: watch drags (`NSEvent` `.leftMouseDragged` + the drag pasteboard) and open on drag-enter. |
| **Now playing** (Music, Spotify) | Distributed notifications the players post themselves: `com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged` | none | *To validate.* Covers Music and Spotify only. System-wide "now playing" (MediaRemote) is a private framework, blocked for third-party apps since macOS 15.4. Play/pause would need Apple Events (Automation permission per player). |
| **Mic / camera in use** | CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere`, CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` | none | Says *that* they are in use, not *which app*. |
| **Battery / charging** | IOKit `IOPSNotificationCreateRunLoopSource` | none | Plugged in, unplugged, low battery. |
| **Next calendar event** | EventKit | Calendar | |
| **Download finished** | Watch `~/Downloads` (FSEvents) | Downloads folder | |
| **Timer / Pomodoro** | Kizami's own state | none | |

## Not possible with public APIs

- **Other apps' notifications and messages** (WhatsApp, Slack, Messages). macOS has no API to read another app's notifications. The workarounds are reading Notification Center through Accessibility, which is fragile and needs a broad permission, or reading Messages' database, which needs Full Disk Access. The supported path is the other way around: an app or script that wants to show up sends an activity to Kizami.
- **Lock screen island.** Needs the private SkyLight framework.
- **Replacing the volume / brightness HUD.** Needs to intercept media keys (Accessibility) and breaks between macOS versions.
