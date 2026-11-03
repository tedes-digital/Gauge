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
| **Claude** | Open Settings (gear icon) → **Open Claude Usage**, then copy the percentages into the app. Claude has no public usage API, so this part is manual. |

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
- **Claude:** shows the snapshot you entered and marks it outdated after one hour. Values are never guessed.
- The notch panel is a visual overlay, not an Apple API. It follows the main display, and macOS fullscreen or system UI can cover it. The menu-bar popover always works.

## Limitations

- Codex CLI output formats may change.
- Global mouse monitoring may be restricted on managed devices; then use the menu-bar item.
- Not an official Anthropic or OpenAI product.
