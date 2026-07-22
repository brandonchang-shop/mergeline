# DevDash

A tiny native macOS menu-bar app (`</>` icon) — your dev dashboard in one click:

- **Open PRs** with review/CI status dots (via `gh`)
- **Merged in the last 7 days**
- **Todos** — add / edit / complete / delete inline (stored in `~/.pi/todo.md`)
- **✨ AI Standup** — generates a spoken standup script from your recent PRs (via `claude`), in a movable window

Built with Swift + SwiftUI + AppKit (`NSStatusItem` + `NSPopover`). Clicks stay in the popover; it closes when you click outside.

## Requirements
- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- [`gh`](https://cli.github.com) authenticated (`gh auth login`)
- [`claude`](https://docs.anthropic.com/en/docs/claude-code) on PATH (for the standup feature)

## Build & run
```bash
./build.sh
open build/DevDash.app
```

## Project layout
- `Sources/main.swift` — app entry, status item, popover, single-instance + outside-click close
- `Sources/Model.swift` — data layer (`gh`/`claude` shellouts, todo file I/O)
- `Sources/ContentView.swift` — SwiftUI UI
- `build.sh` — compiles with `swiftc` into `build/DevDash.app` (ad-hoc signed, menu-bar only)

## Note on managed Macs (Shopify)
Santa Lockdown may block a locally built app. After it's allow-listed, run `santactl sync` then `open build/DevDash.app`. Rebuilds change the binary hash — `santactl sync` again if needed.
