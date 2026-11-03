# Gauge

A tiny macOS menu-bar app that shows how much of your **Claude** and **ChatGPT (Codex)** usage is left. Hover the notch area at the top of the screen, or click the menu-bar item, to see a compact usage card.

- Native AppKit, no Xcode project, no third-party dependencies
- Local only: no servers, no passwords, no browser cookies
- macOS 14 (Sonoma) or newer, Apple Silicon and Intel

## Install

1. Download `Gauge.zip` from the [Releases](../../releases) page and unzip it.
2. Move `Gauge.app` to `/Applications`.
3. The first time, right-click the app → **Open** → **Open** (the app is not notarized).

Then connect your AI accounts:

| Provider | How to connect |
|----------|----------------|
| **ChatGPT / Codex** | Install the [Codex CLI](https://github.com/openai/codex) and run `codex login` with your ChatGPT account. Usage is then read automatically. |
| **Claude (Claude Code)** | Nothing to do. Gauge reads Claude Code's local logs (`~/.claude/projects`) and shows tokens used in the current 5-hour session and the last 7 days. |
| **Claude (claude.ai)** | Optional: Settings (gear icon) → **Open Claude Usage**, then copy the percentages into the app. Fresh manual values take priority. Claude has no public usage API. |

Optional in Settings: notch panel on/off, low-usage notifications (20% / 10% / 0%), auto-refresh interval, Launch at Login.

## Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
swift run Gauge   # run directly
./build-app.sh       # builds dist/Gauge.app and dist/Gauge.zip
```

`build-app.sh` produces a universal, ad-hoc-signed bundle. For Launch at Login and notifications, use the `.app` rather than `swift run`.

## How it works

- **ChatGPT:** talks to the local `codex app-server` over stdio and reads the Codex rate limits. These are Codex limits, not every ChatGPT chat limit. If a refresh fails, the last values stay on screen marked as stale.
- **Claude Code:** parses local transcript logs incrementally (first scan ~3 s, later refreshes milliseconds) and counts input, output and cache-creation tokens. This is token usage, not a percentage of your plan, because Anthropic does not publish subscription limits.
- **Claude manual snapshot:** shown instead of tokens while it is less than one hour old, then marked outdated. Values are never guessed.
- The notch panel is a visual overlay, not an Apple API. It follows the main display, and macOS fullscreen or system UI can cover it. The menu-bar popover always works.

## Limitations

- Codex CLI output formats may change.
- Global mouse monitoring may be restricted on managed devices; then use the menu-bar item.
- Not an official Anthropic or OpenAI product.
