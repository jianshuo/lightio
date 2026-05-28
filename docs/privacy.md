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
