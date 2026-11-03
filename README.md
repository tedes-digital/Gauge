# Gauge

A small macOS menu-bar app that shows how much of your AI usage you have used, at a glance: **Claude Code**, **ChatGPT (Codex)** and **GitHub Copilot**. On a MacBook with a notch it lives in the notch area; hover it and a card unfolds below with details.

- Native AppKit. No Xcode project, no third-party dependencies, nothing to install besides the app itself
- Local only: reads logs and CLIs already on your Mac. No servers, no passwords, no browser cookies
- macOS 14 (Sonoma) or newer, Apple Silicon and Intel

## Features

**At a glance**
- A compact island next to the notch with an icon and a value for each service. On Macs without a notch the values sit in the menu bar instead.
- Hover the island: a card unfolds just below it, separate from the island so it never covers toolbar buttons of the app underneath.
- The card has one row per service with a progress bar for what is left. Hover a row to see a per-project breakdown over the other rows.
- Click the menu-bar icon for the same card. Right-click it for Refresh, Settings and Quit.

**Claude Code**
- Tracks the current 5-hour session and the last 7 days from Claude Code's local logs, with a countdown to the end of the session.
- Shows API-equivalent dollars or raw tokens (your choice in Settings), and a breakdown by project.
- Dollars use Anthropic's public list prices, including cache reads and writes. On Pro, Max and Team plans, which are not billed per token, treat it as the value you get rather than a charge.
- Optional: type the percentages from claude.ai Settings → Usage; fresh manual values take priority.

**ChatGPT (Codex)**
- Reads your real rate limits (5-hour and weekly) from the Codex CLI, with the time until each resets.
- Handles credit-based, unlimited and admin-managed plans instead of failing.
- Per-project token breakdown from local Codex logs.
- Optional notifications at 20%, 10% and 0% left.

**GitHub Copilot**
- Counts premium requests per calendar month from Copilot CLI logs, against your plan's allowance (Free 50, Pro/Business 300, Enterprise 1000, Pro+ 1500, or your own number).
- Optional exact total from GitHub's billing API through your own `gh` login. Gauge never sees a token.

**Other**
- Smooth spring animations, progress bars that turn red when little is left, auto-refresh every 1, 5, 10 or 15 minutes, Launch at Login, and a Quit button.

## Install

1. Download `Gauge.zip` from the [Releases](../../releases) page and unzip it.
2. Move `Gauge.app` to `/Applications`.
3. The first time, right-click the app → **Open** → **Open** (the app is not notarized).

Then make sure the services you use are set up. Gauge reads what these tools already leave on your Mac:

| Service | What you need |
|---------|---------------|
| **Claude Code** | Claude Code installed and used. Nothing to connect. |
| **ChatGPT / Codex** | [Codex CLI](https://github.com/openai/codex) installed and `codex login` done with your ChatGPT account (not an API key). |
| **GitHub Copilot** | Copilot CLI installed and used at least once. For exact totals, install `gh`, run `gh auth refresh -h github.com -s user` and switch the option on in Settings. |

A service that has no data on your Mac simply stays empty or hidden.

## Good to know

- **Claude Code** and **Copilot** numbers cover this Mac only: chats on claude.ai, VS Code chat, other computers and mobile are not visible locally.
- **Copilot** requests are an estimate; GitHub's billing page is authoritative.
- **Dollars** are list prices without discounts, batch, fast mode or paid tools.
- The island is a visual overlay, not an Apple API. macOS fullscreen or system UI can cover it; the menu-bar icon always works.
- Global mouse tracking may be restricted on managed devices; then use the menu-bar icon.
- Not an official Anthropic, OpenAI or GitHub product. Service logos come from [simple-icons](https://github.com/simple-icons/simple-icons) (CC0) and remain trademarks of their owners; they are used only to tell the services apart.

## Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
swift run Gauge        # run directly
./build-app.sh         # builds dist/Gauge.app and dist/Gauge.zip
```

`build-app.sh` produces a universal, ad-hoc-signed bundle. For Launch at Login and notifications, use the `.app` rather than `swift run`.

## How it works

| Service | Source |
|---------|--------|
| Claude Code | local logs in `~/.claude/projects` |
| ChatGPT / Codex | `codex app-server` over local stdio for limits; `~/.codex/sessions` for projects |
| GitHub Copilot | `~/.copilot/session-state`; optionally `gh api` for billing |

Log readers are incremental (the first scan takes a few seconds, later refreshes milliseconds). Adding a service means producing one `ProviderCard` in `AppModel.cards`; the card, island and menu bar pick it up.
