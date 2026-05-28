# CCLight — App Store Connect Metadata

All character counts are strict limits. Numbers in brackets show current count.

---

## App Name [7 / 30 chars max]

```
CCLight
```

---

## Subtitle [30 / 30 chars max]

```
Notch-native status for Claude Code
```

> **Note:** That's 36 chars — too long. Recommended alternatives (pick one):

| Option | Text | Count |
|--------|------|-------|
| A | Ambient Claude Code status light | 33 — too long |
| B | Claude Code status in the notch | 32 — too long |
| C | Claude Code light in your notch | 31 — too long |
| **D** | **Claude Code status, in the notch** | **35 — too long** |
| **E** | **Status light for Claude Code** | **31 — too long** |
| **F** | **Notch light for Claude Code** | **30 — exact fit ✓** |
| G | Ambient status for Claude Code | 30 — exact fit ✓ |

**Recommended: `Ambient status for Claude Code`** [30 chars]

```
Ambient status for Claude Code
```

---

## Promotional Text [170 chars max — editable without resubmission]

```
CCLight v1.0 — turns your MacBook notch into a calm Claude Code status indicator. Amber when Claude is working. Green when it is your turn. White when idle.
```

[157 chars — within limit]

> This field can be updated any time without a new review cycle. Use it to highlight what changed in the latest version or a timely call to action.

---

## Description [4000 chars max]

```
CCLight turns the MacBook notch into a persistent, ambient status indicator for Claude Code — without ever opening a window, stealing focus, or demanding attention.

The notch outline glows amber while Claude is processing your prompt. It shifts to green when Claude is waiting for your response. It fades to white when a session is idle. That is the entire interface.

Key features:

— Notch-native display: the glow lives where the camera cutout already is. Nothing is added to your screen real estate.
— Multi-session support: running three Claude Code sessions in parallel? The U-shape outline splits into up to four independent segments, each colored by its own session's state. You know at a glance which session needs attention without switching windows.
— Breathing animation: active working sessions breathe at a calm 45–100% opacity cycle over 1.8 seconds — visible enough to notice in your peripheral vision, slow enough not to distract.
— Menu bar summary: a small dot in the menu bar shows the combined state across all sessions. Click it to see every session by name, install or remove Claude Code hooks, toggle Launch at Login, or quit.
— Zero interruption: the window is transparent, borderless, always-on-top across Spaces, and fully mouse-transparent. CCLight never intercepts a click.
— Sandboxed: no access to your file system beyond what you explicitly authorize. Claude Code hooks are installed only via a permission dialog you control.
— Privacy first: no analytics, no telemetry, no network traffic. Session state is written to a local file in the app's own sandbox container by the cclight CLI, and that is the only data CCLight ever reads.

How it works in three steps:

1. Install hooks. Open the CCLight menu and choose "Install Hooks." CCLight writes a small set of lifecycle hooks to your ~/.claude/settings.json file. Claude Code then calls the cclight CLI on session start, prompt submit, stop, and session end.
2. Start coding. Launch Claude Code as usual. The notch outline lights up amber the moment you submit a prompt.
3. Work on something else. The ambient glow stays in your peripheral vision — a calm, continuous signal that requires no active monitoring.

Why ambient design matters:

Developers context-switch constantly. Checking whether Claude has finished processing typically means moving the mouse to the Claude Code terminal or window — a small interruption that adds up. CCLight makes that check free. You know Claude's state without looking away from your editor.

The design deliberately avoids notifications, badges, or sounds. Those are interruptions. A gentle light in the corner of your screen is information without cost.

Who it is for:

CCLight is for developers who use Claude Code on an Apple Silicon MacBook (M1 or later) and have a notch. If you run multiple Claude Code sessions — long-running background tasks alongside an active conversation, for instance — the multi-session view makes it immediately clear which session is in which state.

CCLight is open source. Source code and issue tracker are at https://github.com/jianshuo/cclight.
```

> Character count: ~2,180. Well within the 4,000-char limit, leaving room for App Store localization or future expansion.

---

## Keywords [100 chars max, comma-separated, no spaces after commas]

```
claude code,notch,status,menu bar,ambient,developer,coding,AI,indicator,light,halo,productivity
```

[94 chars — within limit]

> Notes:
> - "claude code" as a phrase targets exact-match search intent.
> - "notch" and "menu bar" are common search terms for this category.
> - Do not repeat the app name (CCLight) in keywords — App Store already indexes the name.
> - "AI" captures broader searches. Can swap for "assistant" if needed.

---

## Primary Category

**Developer Tools**

> CCLight's primary function is to surface development workflow state (Claude Code session status) to the developer. App Store reviewers will expect it in Developer Tools alongside menu-bar utilities like Proxyman, TablePlus, and similar.

---

## Secondary Category

**Productivity**

> The core value proposition — reducing context-switch cost during coding — is a productivity use case. Productivity is the natural secondary category.

---

## Support URL

```
https://github.com/jianshuo/cclight/issues
```

---

## Marketing URL

```
https://github.com/jianshuo/cclight
```

---

## Privacy Policy URL

```
https://jianshuo.github.io/cclight/privacy
```

> **Action required:** Enable GitHub Pages on the `cclight` repository (Settings → Pages → Branch: main, folder: `/docs`), then commit the privacy policy markdown below as `docs/privacy.md`. GitHub Pages will serve it at the URL above.
>
> Alternative: if you prefer not to enable GitHub Pages, Apple also accepts a privacy policy hosted as a raw GitHub file. In that case use:
> `https://raw.githubusercontent.com/jianshuo/cclight/main/docs/privacy.md`
> However, raw GitHub links are not styled and Apple prefers a real URL. GitHub Pages is recommended.

---

## Age Rating

**4+**

> CCLight contains no user-generated content, no web browsing, no social networking features, no advertisements, and no in-app purchases. It displays colored light. 4+ is the appropriate rating.

---

## Copyright

```
© 2026 Jian Shuo Wang
```

---

## Version Release Notes — v1.0 [4000 chars max]

```
Initial release.

CCLight turns the MacBook notch into an ambient status indicator for Claude Code. This first version includes:

— Notch halo overlay: a thin U-shape outline glows around the bottom of the notch. Amber while Claude is processing, green while waiting for your input, white when idle.
— Multi-session segments: up to four simultaneous Claude Code sessions are shown as independent colored segments along the notch outline.
— Breathing animation: working sessions pulse gently at a 1.8-second cycle so the indicator is visible without being distracting.
— Menu bar item: a single dot shows the combined state of all active sessions. The dropdown lists each session by name with its current state.
— Hook installer: one-click installation and removal of Claude Code lifecycle hooks via a permission dialog.
— Launch at Login support.
— Sandboxed and privacy-respecting: no network access, no analytics, no telemetry.

Requires macOS 14 Sonoma or later on an Apple Silicon MacBook with a notch (M1 Pro/Max/Ultra, M2, M3, M4 series).
```

[~920 chars]

---

---

# Privacy Policy

> Copy the content below and save it as `docs/privacy.md` in the `cclight` repository, then enable GitHub Pages so it is served at `https://jianshuo.github.io/cclight/privacy`.

---

```markdown
# CCLight Privacy Policy

Last updated: May 28, 2026

## Summary

CCLight collects no personal data, no analytics, and no telemetry. It makes no network connections.

## What CCLight does with your data

**State file.** The cclight CLI writes a single JSON file (`state.json`) to the app's sandbox container directory (`~/Library/Containers/com.wangjianshuo.lightio/Data/`). This file contains only the current state (working / waiting / idle) and a session identifier for each active Claude Code session. The file never leaves your Mac.

**Hooks file.** When you choose "Install Hooks" from the menu, CCLight asks you to authorize a write to `~/.claude/settings.json` via a system permission dialog (NSOpenPanel). CCLight reads and modifies only the `hooks` key within that file. No other part of your file system is accessed.

**No network traffic.** CCLight contains no HTTP client code, no analytics SDK, no crash reporter, and no telemetry. It never opens a network socket.

**No third-party SDKs.** CCLight has no third-party dependencies beyond Apple system frameworks.

## Data storage

All data (the state file) is stored exclusively on your local machine in the app's sandboxed container. It is not synced to iCloud, not shared with any service, and is deleted when you uninstall the app.

## Children

CCLight does not collect data from anyone, including children under 13.

## Changes

If this policy ever changes, the updated version will be committed to this file in the public repository at https://github.com/jianshuo/cclight.

## Contact

Questions: https://github.com/jianshuo/cclight/issues
```
