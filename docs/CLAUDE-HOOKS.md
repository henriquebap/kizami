# Claude Code sessions on the island

Kizami shows your running Claude Code sessions on the open island: the folder, the state (working, needs you, ready) and for how long. When a session starts waiting for a permission, it also lands in the island's list until you answer. Clicking a session brings it to the front: its own tab in Terminal and iTerm2, the app in VS Code and the Claude app.

It works through [Claude Code hooks](https://code.claude.com/docs/en/hooks): at each event, Claude Code runs `Kizami claude` with the event's JSON on stdin. Kizami's own binary reads it, keeps a few fields and posts them to the running app.

## Install

Add this to the `hooks` key of `~/.claude/settings.json` (merge it with any hooks you already have):

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude", "async": true }] }
    ],
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude", "async": true }] }
    ],
    "PreToolUse": [
      { "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude", "async": true }] }
    ],
    "PostToolUse": [
      { "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude", "async": true }] }
    ],
    "PostToolUseFailure": [
      { "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude", "async": true }] }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt|elicitation_dialog|elicitation_url_dialog",
        "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude", "async": true }]
      }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude", "async": true }] }
    ],
    "StopFailure": [
      { "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude", "async": true }] }
    ],
    "SessionEnd": [
      { "hooks": [{ "type": "command", "command": "/Applications/Kizami.app/Contents/MacOS/Kizami claude" }] }
    ]
  }
}
```

New sessions pick it up; running ones need a restart.

- **`"async": true`** runs the hook in the background, so Claude never waits for Kizami. `SessionEnd` is the exception: Claude Code is exiting, and a background hook could be cut off before it posts. It takes a few milliseconds, well inside the 1.5 s that Claude Code gives `SessionEnd` hooks.
- **`Kizami claude` always exits 0 and prints nothing.** A non-zero exit would show a hook error in the conversation, and text printed during `SessionStart` or `UserPromptSubmit` would be added to Claude's context. If Kizami isn't running, the message simply goes nowhere.
- If you uninstall Kizami, remove this block too: the shell would fail to find the binary and Claude Code would show a hook error on every event.

## What each event does

| Hook event | State on the island |
|---|---|
| `SessionStart` | The session appears as *ready*. A `SessionStart` for a session already on the island (after a compaction, for example) doesn't change its state. |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure` | *working* |
| `Notification` `permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog` | *needs you*: the session goes to the top and an alert stays in the island's list until the state changes |
| `Notification` `idle_prompt` | *ready* |
| `Stop`, `StopFailure` | *ready*; coming from *working*, a short "Claude finished" line shows for a few seconds |
| `SessionEnd` | The session leaves the island |

- **Subagents.** A tool call inside a subagent (the JSON carries `agent_id`) only takes the session out of *needs you*, because it means the permission was answered. It never turns *working* back on, since a background subagent keeps running after the session's `Stop`.
- **When the notifications fire.** Claude Code sends `permission_prompt` after the prompt has waited about six seconds without you typing, and `idle_prompt` about 60 seconds after Claude finishes. So *needs you* means you look away, not that you're at the terminal answering.
- **Esc and stale states.** Claude Code doesn't send `Stop` when you interrupt with Esc. So a session with no event for 20 minutes goes from *working* to *ready*, and *needs you* turns into *ready* (and its alert leaves the island) after 15 minutes. The next event puts the right state back.
- **Late events.** Hooks are async, so a `Stop` can arrive after `SessionEnd`. Events for a session that ended in the last minute are ignored, except a new `SessionStart` (a `--resume`).
- **Expiry.** A *ready* session leaves after 30 minutes. Any session with no event for 3 hours leaves too, because `SessionEnd` gets lost when a terminal is killed or Kizami wasn't running. The next event brings a session back.
- **Other events** (`SubagentStop`, `PreCompact`, other notification types…) are ignored, so it is safe to point more hooks at `Kizami claude`.

## What crosses over, and what never does

`Kizami claude` reads the hook JSON (up to 4 MB; anything bigger is dropped) and sends the app only:

| Field | From |
|---|---|
| `id` | `session_id` |
| `pasta` | the last path component of `cwd` (the folder name, not the full path) |
| `evento` | `hook_event_name`, plus `notification_type` and whether `agent_id` is present |
| `app` | the bundle id of the first app among the hook's parent processes (Terminal, VS Code, Claude…), so a click can bring it to the front |
| `tty` | the terminal device of the session (`ttys003`), so a click can select that tab in Terminal or iTerm2. Absent when the session has no terminal |

**Never sent:** the prompt, Claude's replies (`last_assistant_message`), the notification text (`message`, `title`), tool names, inputs and outputs, the transcript path, the full working directory. Nothing leaves the Mac: the message goes to the Kizami app through a local distributed notification.

Any process on the Mac can post that notification, so the app treats it as data: it accepts at most 4 KB, an id of letters, digits, `-` and `_` (48 characters at most), a cleaned and shortened folder name, a known event, a well-formed bundle id and a tty of the form `ttys` plus 1 to 4 digits. It shows the folder name as plain text, only ever uses the bundle id to activate an app that is already running, and the tty is the only outside text in the AppleScript that selects the tab.

The app logs counts and states, never folder names.

## Not possible

- **Answering a permission prompt from the island.** Claude Code has no public way in; the click brings the session's app to the front so you can answer there.
- **The exact window in VS Code and the Claude app.** Terminal and iTerm2 get the session's tab (Automation, asked on the first click; denied, the app comes forward). VS Code's documented link opens in whichever window has focus, and the Claude app documents no link to an existing session, so both get the app.
