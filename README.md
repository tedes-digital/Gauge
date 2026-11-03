# AI Usage Monitor — AppKit edition (no Xcode / NotchKit dependency)

## What it does

Native menu-bar app for macOS 14+, with a compact rounded usage card in the menu-bar popover and top-center notch panel. The notch card expands on hover and shares the same provider summary, refresh control and settings shortcut. Includes Codex rate-limit readout, manual Claude subscription entries, reset countdown in Settings, auto-refresh, notification thresholds, and Launch at Login (when bundled).

- **Claude:** manual snapshot of 5-hour + weekly percentages from Claude Settings → Usage. Never represented as live data. When 1 hour old, marked potentially outdated. Reset countdown does NOT reset the stored percent.
- **ChatGPT:** reads *Codex* limits only through local `codex app-server` stdio RPC. Not general ChatGPT chat limits, and not spending balance. If unavailable, says so. Last successful values remain but are visibly stale.
- Local-only, no passwords/cookies, no server and no third-party Swift dependencies.
- Menu bar and notch can be temporarily covered/hidden by macOS fullscreen or system UI, depending on display configuration. Notch panel is a visual imitation, not an Apple Dynamic Island API.

## Run in VS Code, using Apple Command Line Tools

Open this directory in VS Code. Terminal commands:

```bash
swift --version
swift build
swift run AIUsageMonitor
```

No Apple Account or Xcode GUI is needed **if the installed Command Line Tools are capable of compiling AppKit on your Mac**. Compilation was syntax-checked on Linux, but cannot be fully linked/run in this environment because Apple frameworks aren't present. If AppKit compilation itself fails, the CLT installation may be insufficient and require company IT support.

## Create a local .app

```bash
./build-app.sh
open dist/AIUsageMonitor.app
```

This builds a self-contained local `.app` with an ad-hoc signature, **not** a notarized distributable app. Depending on corporate macOS policy, Gatekeeper/MDM may restrict it. To register Launch at Login reliably, move the bundle into `/Applications` or `~/Applications` before enabling it (where company policies allow).

The app uses macOS system notification permission; when running as a raw Swift executable notifications can fail to appear. Try the `.app` bundle.

## Codex

Install the Codex CLI through your approved method and authenticate with your ChatGPT subscription (`codex login`). Ensure `codex app-server` works. Without Codex CLI, Claude and the UI still work, while Codex shows an error.

## If compilation fails

Save the output:

```bash
swift build 2>&1 | tee build.log
grep -n 'error:' build.log | head -25
```

Unlike the first version, this package does not include NotchKit, SwiftUI, `#Preview`, `@State`, or any external Swift package dependencies.

## Current limitations

- AppKit notch is a custom overlay; pointer proximity is checked with a global mouse-move event monitor. macOS may limit global mouse monitoring on managed devices, in which case the menu-bar popover still works.
- Notch location uses the primary screen center and needs testing on different multi-monitor layouts and menu-bar configurations.
- No data is read automatically from Claude Pro/Max subscriptions.
- Codex CLI response formats may change; no guarantee of access to all ChatGPT model quotas.
- The app is not an official Anthropic or OpenAI product.
