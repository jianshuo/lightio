# Vibelight — Design Spec

Date: 2026-05-28
Author: Jianshuo Wang (brainstormed with Claude)
Status: Draft

## 1. What we're building

A macOS menu-bar app that turns the physical notch on MacBook Pro / Air into a
status indicator for Claude Code. A thin glowing line under the notch changes
color to show whether Claude Code is busy, waiting for the user, or idle.

Design intent: low-key, ambient, peripheral-vision-only. No popovers, no
notifications, no sound. Just a colored halo you can glance at.

V1 ships as a local-install `.dmg`. App Store submission, full icon assets,
and marketing materials are V2 (per `MACAPP.md`).

## 2. Three states

| State    | Meaning                                                 | Hooks that enter it                |
|----------|---------------------------------------------------------|------------------------------------|
| WORKING  | Claude is busy: LLM call or tool run in progress        | `UserPromptSubmit`                 |
| WAITING  | Claude needs the user (permission, idle after a turn)   | `Stop`, `Notification`, `SessionStart` |
| IDLE     | WAITING for >5 minutes, or no active session            | timer in app, or `SessionEnd`      |

Transitions on a single session:

```
                ┌─────────┐
                │  IDLE   │ ◄── 5min WAITING with no change
        ┌───────┤         │
        │       └─────────┘
        │            ▲
        │            │ UserPromptSubmit
        ▼            │
   ┌─────────┐   ┌─────────┐
   │ WORKING ├──►│ WAITING │
   └─────────┘   └─────────┘
        ▲            │
        └────────────┘
           UserPromptSubmit
```

Multi-session resolution (default): the overlay shows the *highest priority*
state across all known sessions.

```
WORKING > WAITING > IDLE
```

So if any session is WORKING the notch glows green; only when every session
is IDLE does the notch dim.

## 3. Visual spec

### Palette

| State    | Color hex  | Notes                                |
|----------|------------|--------------------------------------|
| WORKING  | `#5fcf7a`  | 草绿                                  |
| WAITING  | `#f5a623`  | 琥珀                                  |
| IDLE     | `#cccccc` @ 0.15 opacity | Barely visible, but present |

### Geometry

- `NSWindow`: borderless, transparent, level `.statusBar + 1`,
  `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`,
  `ignoresMouseEvents = true`, `backgroundColor = .clear`.
- Position: `NSScreen.main.safeAreaInsets` → derive notch rect, then
  `notchRect.insetBy(dx: -40, dy: -40)` to leave room for glow spill.
- Rendering: pure `CALayer` tree (no SwiftUI redraws):
  - `glowLayer` with `shadowColor`, `shadowOpacity = 1`, `shadowRadius = 18`,
    plus a secondary outer layer with `shadowRadius = 32` for soft falloff.
  - `thinLineLayer`: 1pt solid line hugging the notch's lower curve, slightly
    more opaque than the glow, gives the eye a focal point.
- Mask: the root layer is clipped to the notch's lower-half outline so the
  glow appears to *emanate from the notch* rather than floating below it.

### Ding pulse (state-change animation)

A 350ms `CAKeyframeAnimation` on `shadowColor` and `shadowOpacity`:

```
t=0ms     current color, opacity 1.0
t=150ms   white,         opacity 1.0   (ease-out)
t=350ms   new color,     opacity 1.0   (ease-in)
```

If a new state change arrives mid-pulse, the running animation is cancelled
and a new one starts from the current interpolated values.

### Accessibility

- If `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is true,
  ding pulse shortens to a 50ms instant color swap.
- IDLE never goes fully black — keeps a 15%-opacity gray glow so the user
  knows the app is alive.

### Fullscreen / video / games

No special handling. The system naturally hides the window during exclusive
fullscreen (which is the desired behavior — don't distract during movies).

### Light/dark mode

Notch is a physical black cutout; appearance mode does not affect colors.

## 4. Architecture

Four components, all in one `.app` bundle:

```
┌─────────────────────────────────────────────────────────────┐
│ vibelight.app  (LSUIElement = true, no Dock icon)           │
│                                                             │
│  ┌──────────────┐    FSEvents    ┌────────────────────┐    │
│  │  StateStore  │ ◄────────────  │ ~/.vibelight/      │    │
│  │              │                │   state.json       │    │
│  │ - debounce   │                └────────────────────┘    │
│  │ - merge      │                          ▲                │
│  │   sessions   │                          │ atomic write   │
│  │ - 5min timer │                          │                │
│  └──────┬───────┘                ┌─────────┴────────┐       │
│         │ publishes              │  vibelight CLI    │       │
│         │ CurrentState           │  (bundled binary, │       │
│         ▼                        │   symlinked to    │       │
│  ┌──────────────┐                │   /usr/local/bin) │       │
│  │ NotchOverlay │                └─────────┬────────┘       │
│  │              │                          ▲                │
│  │ - NSWindow   │                          │ shell exec     │
│  │ - CALayer    │                ┌─────────┴────────┐       │
│  │ - animator   │                │ ~/.claude/       │       │
│  └──────────────┘                │   settings.json  │       │
│                                  │   (hook configs) │       │
│  ┌──────────────┐                └──────────────────┘       │
│  │ MenuBarItem  │                                            │
│  │              │                                            │
│  │ - status dot │                                            │
│  │ - menu       │                                            │
│  └──────────────┘                                            │
└─────────────────────────────────────────────────────────────┘
```

### Component: CLI (`vibelight`)

Swift binary, ~50KB. Bundled inside `vibelight.app/Contents/Resources/vibelight`.
On first launch the app installs a symlink to `/usr/local/bin/vibelight`
(requires admin password once, via `STPrivilegedTask` or `osascript`).

Commands:

| Command                          | Effect                                                                       |
|----------------------------------|------------------------------------------------------------------------------|
| `vibelight set <working|waiting>`| Reads Claude Code's hook-input JSON on stdin, extracts `session_id` + `cwd`, atomic-writes that session's entry into state.json. Falls back to session id `"default"` if stdin is empty (for dev testing). |
| `vibelight clear`                | Same input handling; removes the session entry                               |
| `vibelight status`               | Print current state.json (debug, ignores stdin)                              |
| `vibelight install-hooks`        | Patch `~/.claude/settings.json` to add hooks                                 |
| `vibelight uninstall-hooks`      | Remove vibelight hooks from settings.json                                    |

Atomic write: write to `state.json.tmp.<pid>` then `rename(2)` over `state.json`.
This guarantees the FSEventStream consumer never sees a half-written file.

### Component: StateStore

Singleton inside the app. Watches `~/.vibelight/state.json` via
`FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`. On every
change:

1. Read + parse state.json. If the file is missing or empty, treat as
   `{sessions: {}}` → merged IDLE.
2. Run multi-session merge: priority order WORKING > WAITING > IDLE; the
   strongest state across all sessions wins.
3. If merged state changed, publish `CurrentState` to observers (Combine).
4. Manage the idle timer:
   - merged WORKING → cancel any running idle timer
   - merged WAITING → (re)start a 5-minute idle timer
   - merged IDLE → no timer needed

The 5-minute timer is a `DispatchSourceTimer`. When it fires, the published
`CurrentState` is downgraded to IDLE without touching state.json (the timer
is a presentation-layer concern only — incoming `set working` from any
session immediately overrides).

### Component: NotchOverlay

`NSWindowController` + custom `NSView`. Subscribes to `StateStore.currentState`.
On change, runs the ding-pulse `CAKeyframeAnimation` then settles into the
new color. Positioning recomputes on screen changes (`NSApplication.didChangeScreenParametersNotification`).

### Component: MenuBarItem

`NSStatusItem` with variable-length button. The button image is a small
filled circle matching the current state color.

Menu:

```
● vibelight                                  ← colored dot matching state
─────────────────
当前状态: WORKING (1 个 session)
─────────────────
Install Claude Code Hooks
Uninstall Claude Code Hooks
─────────────────
Launch at Login                            ✓
─────────────────
About vibelight
Quit
```

## 5. Data formats

### `~/.vibelight/state.json`

```json
{
  "version": 1,
  "sessions": {
    "abc123-session-uuid": {
      "state": "working",
      "ts": 1779944100,
      "cwd": "/Users/jianshuo/code/vibelight"
    },
    "def456-session-uuid": {
      "state": "waiting",
      "ts": 1779944220,
      "cwd": "/Users/jianshuo/code/foo"
    }
  }
}
```

- `state`: one of `"working" | "waiting"`. (IDLE is presentation-only; never
  written to file.)
- `ts`: Unix seconds.
- `cwd`: optional, helps debugging. Read from the `cwd` field in Claude
  Code's stdin JSON payload.

### Hook config patch to `~/.claude/settings.json`

```json
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "vibelight set waiting"}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "vibelight set working"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "vibelight set waiting"}]}
    ],
    "Notification": [
      {"hooks": [{"type": "command", "command": "vibelight set waiting"}]}
    ],
    "SessionEnd": [
      {"hooks": [{"type": "command", "command": "vibelight clear"}]}
    ]
  }
}
```

Claude Code pipes a JSON payload to each hook's stdin containing
`session_id`, `cwd`, `hook_event_name` etc. The `vibelight` CLI reads that
JSON to identify the session.

The installer merges with existing hooks (does not clobber). Original
settings.json is backed up to `settings.json.vibelight-backup` once.

## 6. First-run UX

1. User drags `vibelight.app` from `.dmg` into `/Applications`, double-clicks.
2. App checks `/usr/local/bin/vibelight`:
   - Missing → dialog: "需要把 CLI 安装到 `/usr/local/bin/vibelight`，
     这一步需要管理员密码。" → user approves → admin-elevated `ln -s`.
3. App checks `~/.claude/settings.json`:
   - Exists → dialog: "检测到 Claude Code，是否自动加入 vibelight 的 hooks？
     原文件会备份到 `settings.json.vibelight-backup`。" → user approves →
     CLI's `install-hooks` runs.
   - Missing → dialog skipped; "Install Hooks" menu item remains for later.
4. `SMAppService.mainApp.register()` to enable Launch at Login.
5. Notch glows green for 1 second as a self-test, then transitions to IDLE.

## 7. Build & ship (V1)

- **Target**: macOS 14+ (Sonoma) — needed for safe-area APIs.
- **Project**: existing `vibelight.xcodeproj` (SwiftUI scaffold — to be
  largely replaced; only `App` entry point is reused).
- **Distribution**: signed `.dmg` from local Developer ID (not App Store).
- **No sandbox** in V1 (needed for the `/usr/local/bin` symlink).
- **Min build**: `xcodebuild -scheme vibelight build`. Manual smoke test on
  the dev machine.

## 8. Out of scope for V1

- Color customization in settings
- Multi-session bisected display (e.g., notch split in two colors)
- Notification Center popups, sounds, badge counts
- Sandbox / hardened runtime / notarization
- App Store submission and marketing assets
- Universal binary for Intel Macs (Apple Silicon only, no notch on Intel)
- Windows / Linux

## 9. V2 (covered by `MACAPP.md`)

- Generate logo via `gpt-image-2` skill, slice to AppIcon set
- App Store sandbox compliance: CLI install changes from symlink to a
  user-action (user adds bundle path to PATH manually, or copies hook
  config from app)
- Hardened runtime, notarization, Developer ID → App Store distribution
- Screenshots, App Store description, keywords, support URL
- Apple Silicon-only marketing copy

## 10. Risks & open questions

1. **Notch geometry on different MacBooks**: M1 14"/16", M2 13"/15" Air,
   M3/M4 lines all have slightly different widths. The `safeAreaInsets` API
   should give us the right rect, but we should test on at least the user's
   M4 14" and verify. If `safeAreaInsets` doesn't expose it cleanly on a
   non-fullscreen window, fall back to `NSScreen.auxiliaryTopLeftArea` /
   `auxiliaryTopRightArea`.
2. **Symlink + sudo**: requesting admin password on first launch is a UX
   hit. Alternative: drop the symlink and have the hook config use the
   full path `/Applications/vibelight.app/Contents/Resources/vibelight`.
   Cleaner but more brittle if user renames the app. Default to symlink,
   but expose this in install-hooks via a `--no-symlink` flag.
3. **FSEvents latency**: typically <100ms but can spike. Acceptable for
   ambient indicator.
4. **What if a hook fires for a non-Claude-Code process named claude?**
   Hooks only fire from Claude Code, so this isn't a real concern.
5. **No way to suppress overlay temporarily** in V1 — if it's distracting
   (e.g., screen recording), user must Quit from menu bar. Acceptable for V1.
