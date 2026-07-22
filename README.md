# Mergeline

A tiny native macOS menu-bar app (`</>` icon) — your PRs, reviews, todos, and standup in one click:

- **Open PRs** with review/CI status dots (via `gh`)
- **Review Requests** — open PRs awaiting your review
- **Merged** in the last N days (configurable in Settings)
- **Todos** — add / edit / complete / delete inline (stored in `~/.pi/todo.md`)
- **✨ AI Standup** — generates a Shipped / Working on / Blockers standup from your recent PRs (via `claude`), in a movable window

Built with Swift + SwiftUI + AppKit (`NSStatusItem` + `NSPopover`). Clicks stay in the popover; it closes when you click outside. Launches at login automatically.

## Requirements
- macOS 13+
- Xcode Command Line Tools — `xcode-select --install` (provides the `swiftc` compiler)
- [`gh`](https://cli.github.com) authenticated — `gh auth login`
- [`claude`](https://docs.anthropic.com/en/docs/claude-code) on PATH — optional, only for the AI Standup feature

## Install (build from source)

> **Important:** build it yourself — don't copy a pre-built `Mergeline.app` from someone else.
> On Shopify-managed Macs (Santa Lockdown), a binary is only trusted if it was compiled
> locally by the allow-listed `swiftc`. Your own build is auto-trusted; a copied `.app` is blocked.

```bash
# 1. one-time setup (skip anything you already have)
xcode-select --install
gh auth login

# 2. clone, build, run
git clone https://github.com/brandonchang-shop/mergeline.git ~/Mergeline
cd ~/Mergeline
./build.sh
open build/Mergeline.app
```

The `</>` icon appears in your menu bar. Click it. Done.

## Updating
```bash
cd ~/Mergeline
git pull
./build.sh
open build/Mergeline.app
```
No re-approval needed — each local build is auto-trusted.

## Troubleshooting

**App won't open / "cannot be opened" (Shopify-managed Mac, Santa Lockdown):**
This should not happen when you build from source, but if it does:

1. Confirm transitive allow-listing is on:
   ```bash
   santactl status | grep -i transitive
   ```
   You should see a nonzero `Transitive Rules` count. (This is what auto-trusts `swiftc` output.)
2. Check the binary's rule:
   ```bash
   santactl fileinfo build/Mergeline.app/Contents/MacOS/Mergeline | grep -Ei 'rule|sha-256'
   ```
   `Rule: None` = not trusted yet. Rebuild cleanly with `./build.sh` (do **not** run `codesign` on it — that changes the hash and breaks the trust rule).
3. If it's still blocked, request a one-time allow via the Tool Catalog: https://tool-catalog.it.shopify.io/propose

**Empty PR lists:** make sure `gh auth login` succeeded — the data comes from the GitHub CLI.

**Standup says it failed:** the `claude` CLI isn't on your PATH; install it or ignore (the rest works without it).

## Project layout
- `Sources/main.swift` — app entry, status item, popover, single-instance + outside-click close
- `Sources/Model.swift` — data layer (`gh`/`claude` shellouts, todo file I/O)
- `Sources/ContentView.swift` — SwiftUI UI
- `build.sh` — compiles with `swiftc` into `build/Mergeline.app` (menu-bar only; **no codesign** — see Troubleshooting)
