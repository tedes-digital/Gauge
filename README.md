# Gauge

**Gauge shows how much of your AI tools you have used, right at the top of your Mac screen.**

It works with **Claude Code**, **ChatGPT (Codex)** and **GitHub Copilot**. You glance at the top of the screen, you see the numbers, you move on. No windows to open, no websites to visit.

On a MacBook with a notch, the numbers sit next to the notch. Move the mouse onto them and a small card opens with more detail.

> You do not need to be technical to use Gauge. This guide explains every step in plain words.

---

## Contents

1. [Is it safe? Your privacy](#1-is-it-safe-your-privacy)
2. [What you need](#2-what-you-need)
3. [Install Gauge](#3-install-gauge)
4. [Open Gauge and find it on screen](#4-open-gauge-and-find-it-on-screen)
5. [Start Gauge automatically when you turn on your Mac](#5-start-gauge-automatically-when-you-turn-on-your-mac)
6. [Connect your AI tools](#6-connect-your-ai-tools)
7. [How to read the card](#7-how-to-read-the-card)
8. [Settings, one by one](#8-settings-one-by-one)
9. [Understanding the numbers](#9-understanding-the-numbers)
10. [Something is not working](#10-something-is-not-working)
11. [Quit and uninstall](#11-quit-and-uninstall)
12. [For developers](#12-for-developers)

---

## 1. Is it safe? Your privacy

Short answer: **yes. Gauge keeps everything on your Mac.**

- **No cookies.** Gauge never looks at your web browser, your logins or your cookies.
- **No passwords.** It never asks for a password, a key or a token, and it never stores one.
- **No data collected.** There is no tracking, no analytics and no account. Nothing about you or your usage is sent to the author or to anyone else.
- **No internet connection of its own.** Gauge does not talk to any server. The only time it touches the web is when *you* press the button **Open Claude Usage**, which simply opens a web page in your browser.
- **Open source.** Every line of the program is public on GitHub, under the free [MIT license](LICENSE). Anyone can read it, check it, and build the app themselves. You do not have to take our word for it.

**What Gauge actually does:** it reads small "history" files that your AI tools already save on your own Mac (for example, a note each time Claude Code answers you), and adds them up. It only *reads* them. It never changes or deletes them.

Two optional features ask a program you already have for numbers:

- **ChatGPT limits** come from the Codex program on your Mac. That program talks to OpenAI the way it always does. Gauge only asks it for the result.
- **Exact GitHub Copilot totals** (switched off by default) come from GitHub's own `gh` program, using the login you already have. Gauge never sees your password or token.

The names of your project folders may appear on the card. They come from those history files and stay on your Mac.

---

## 2. What you need

- A **Mac** with **macOS 14 (Sonoma) or newer**. To check: click the Apple logo in the top-left corner → **About This Mac**. Both Apple Silicon (M1, M2, M3, M4...) and older Intel Macs work.
- At least **one** of these AI tools, already installed and used on this Mac. You do not need all three:
  - **Claude Code**
  - **ChatGPT through the Codex program**
  - **GitHub Copilot through the Copilot command-line tool**

If a tool is not on your Mac, Gauge simply does not show it.

> **Good to know:** Gauge sees what happens *on this Mac*. Chatting on a website (like claude.ai or chatgpt.com), in your phone app, or on another computer is not counted.

---

## 3. Install Gauge

1. Open the [Releases page](../../releases) and download **Gauge.zip** from the newest release (under **Assets**).
2. Open your **Downloads** folder and **double-click Gauge.zip**. A file called **Gauge** (with a gauge icon) appears next to it.
3. **Drag Gauge into your Applications folder.** (Open Finder, click **Applications** in the left column, and drop Gauge there.) This step matters: automatic start and notifications only work from the Applications folder.

### The first time you open it: macOS will show a warning

Gauge is a free app that Apple has not reviewed ("notarized"), so macOS asks you to confirm it. This is normal and happens once.

**On macOS 15 (Sequoia) or newer:**

1. Open **Applications** and double-click **Gauge**.
2. A message says the app cannot be verified. Click **Done** (do not click "Move to Trash").
3. Click the Apple logo → **System Settings** → **Privacy & Security**.
4. Scroll down to the **Security** section. You will see "Gauge was blocked". Click **Open Anyway**.
5. Type your Mac password (or use Touch ID) and click **Open Anyway** once more.

**On macOS 14:**

1. Open **Applications**, **hold the Control key and click Gauge** (or right-click it), then choose **Open**.
2. Click **Open** in the message.

After that, Gauge opens normally every time.

---

## 4. Open Gauge and find it on screen

Gauge does not open a big window and does not appear in the Dock at the bottom. It lives at the very top of the screen. Right after you open it, look there.

**On a MacBook with a notch:** look at the notch. To its left you will see a small black area with a logo and a number for each tool you use. In the menu bar (the strip at the very top) you will also see a small **gauge icon**.

**On a Mac without a notch:** the numbers appear in the menu bar at the top, each with its tool's logo. A small black pill with the same numbers also sits at the top centre of the screen (you can turn it off in Settings).

### Open the card

- **Move the mouse onto the numbers** next to the notch. A card unfolds just below. Move the mouse away and it folds back.
- Or **click the gauge icon / numbers in the menu bar**. The same card opens. Click anywhere else to close it.

### The buttons on the card

| Button | What it does |
|--------|--------------|
| ⟳ (bottom right) | Reload the numbers right now |
| ⚙ (top right, gear) | Open Settings |
| ⏻ (top right, power) | Quit Gauge |

### The menu-bar menu

**Right-click** the gauge icon (or **Control-click**) to get a small menu: **Refresh**, **Settings…** and **Quit Gauge**.

### Open it again later

If you quit Gauge, open it again from **Applications**, from **Launchpad**, or press **⌘ Space** (Command + Spacebar), type **Gauge**, and press **Return**.

> **Cannot see the icon?** When the menu bar is crowded, macOS hides some icons behind the notch. Hold the **⌘ Command** key and drag a few icons you do not need out of the menu bar, or quit an app that has many icons.

---

## 5. Start Gauge automatically when you turn on your Mac

You can have Gauge open by itself every time you log in, so it is always there.

1. Make sure Gauge is in your **Applications** folder (see step 3).
2. Open Gauge's **Settings** (click the gear on the card, or right-click the menu-bar icon → **Settings…**).
3. Scroll to **App behavior** and tick **Launch at Login**.

To turn it off, untick the same box.

If the tick does not stay on, add it yourself in macOS: Apple logo → **System Settings** → **General** → **Login Items** → click **+** under "Open at Login" → choose **Gauge** from Applications.

---

## 6. Connect your AI tools

"Connecting" here just means: the tool is installed on your Mac and you have signed in to it. **Gauge has no login screen of its own.** It simply finds what the tool already left on your Mac.

### Claude Code: nothing to do

If you use Claude Code, Gauge shows it automatically. It adds up what you used in the current 5-hour session and in the last 7 days.

You can also type in the percentages from the Claude website; see [Settings](#claude-manual-numbers).

### ChatGPT (Codex): one-time setup

For ChatGPT, Gauge needs the **Codex** program, signed in with your **ChatGPT account** (not an API key).

You only do this once. It uses an app called **Terminal**, which is already on your Mac. Terminal is a window where you type short instructions. You will only copy, paste and press Return.

1. **Install Codex.** Follow the *Installation* section at [github.com/openai/codex](https://github.com/openai/codex). It tells you the exact line to paste.
2. **Open Terminal:** press **⌘ Space**, type **Terminal**, press **Return**.
3. **Sign in:** copy this line, click in the Terminal window, paste with **⌘ V**, and press **Return**:

   ```
   codex login
   ```

4. Your web browser opens. Sign in with your ChatGPT account and approve.
5. Back in Gauge, click ⟳. The ChatGPT row now shows how much of your limit is left, and when it resets.

If you do not use Codex, simply skip this. The ChatGPT row will say it is unavailable, or you can ignore it.

### GitHub Copilot: nothing to do (if you use its command-line tool)

If you use the **GitHub Copilot command-line tool** (see [GitHub's Copilot docs](https://docs.github.com/copilot)), Gauge counts your requests automatically, month by month. A "Copilot" row appears once the tool has been used on this Mac.

Copilot in **VS Code**, on **github.com** or on your **phone** is not visible to Gauge. If you use those too, the number will be lower than the real one. For the real total, see the next part.

#### Optional: exact Copilot total from GitHub

This is switched off by default. It asks GitHub for your real number, including VS Code and the website.

1. Install GitHub's `gh` tool from [cli.github.com](https://cli.github.com) and sign in. In Terminal (see above), run: `gh auth login`.
2. In Terminal, run:

   ```
   gh auth refresh -h github.com -s user
   ```

   GitHub asks for a permission called "user". GitHub requires it for billing numbers. If you are not comfortable with it, simply skip this step: Gauge works fine without it.
3. In Gauge's Settings, tick **Exact total from GitHub billing**.

If it does not work (for example because your company manages your GitHub account), Gauge tells you why in Settings and keeps using the numbers from your Mac.

---

## 7. How to read the card

The card has one row per tool. Each row has:

- **The tool's logo and name** (Claude, ChatGPT, Copilot).
- **A line of text on the right**, for example `$10.8 · 1h 18m`.
- **A coloured bar** underneath. It turns **red** when little is left.

What the text means for each tool:

| Tool | Text | Meaning |
|------|------|---------|
| **Claude** | `$10.8 · 1h 18m` | What this 5-hour session cost at normal public prices, and how long until the session ends. In tokens mode, it shows a token count instead of dollars. |
| **Claude** (idle) | `Idle · $270 / 7d` | No session is running. This is the total for the last 7 days. |
| **Claude** (with percentages typed in) | `62% left` | The percentage you copied from the Claude website. |
| **ChatGPT** | `79% left · 3d 4h` | How much of your limit is left, and when it resets. |
| **Copilot** | `12 / 300 req` | Requests used this month out of your monthly allowance. |

**Move the mouse onto a row** to see a breakdown: which projects used how much. For ChatGPT it also shows both limits (the 5-hour one and the weekly one) with their reset times.

The numbers next to the notch are the same values in short form.

---

## 8. Settings, one by one

Open Settings with the **gear** on the card, or right-click the menu-bar icon → **Settings…**.

### Claude Code

| Setting | What it does |
|---------|--------------|
| **Track Claude Code usage from local logs** | On: Gauge reads Claude Code's history on your Mac and shows your usage. Off: Gauge stops reading it. |
| **Claude Code shows** | Choose **Dollars (API list prices)** or **Tokens**. Dollars shows what your usage would cost at Anthropic's public prices. Tokens shows the raw amount of text processed. Plans like Pro, Max and Team are not billed per token, so for them dollars is a guide to the value you get, not a charge. |

### Claude manual numbers

<a id="claude-manual-numbers"></a>

Optional. Claude's website shows your real limit as percentages, but programs cannot read them. If you want them in Gauge, copy them by hand. A recent manual value (less than an hour old) is shown instead of the dollars or tokens.

| Setting | What it does |
|---------|--------------|
| **5-hour remaining** | The percentage left in your 5-hour window, as shown on Claude's usage page. |
| **Weekly remaining** | The percentage left for the week. |
| **Session reset** | When your 5-hour window resets. |
| **Save snapshot** | Saves the three values above. |
| **Clear** | Deletes the saved values. |
| **Open Claude Usage** | Opens Claude's usage page in your browser so you can copy the numbers. |

### ChatGPT (Codex)

| Setting | What it does |
|---------|--------------|
| **Refresh Codex now** | Asks Codex for fresh numbers right away. |

### GitHub Copilot

| Setting | What it does |
|---------|--------------|
| **Track GitHub Copilot CLI requests** | On: counts your requests from the Copilot command-line tool, month by month. Off: hides the Copilot row. |
| **Exact total from GitHub billing (uses your gh login)** | Off by default. On: asks GitHub for your real total, including VS Code and the website. Needs the one-time setup in [section 6](#optional-exact-copilot-total-from-github). |
| **Monthly requests** | Your plan's monthly allowance. Pick one (Free 50, Pro or Business 300, Enterprise 1000, Pro+ 1500) or type your own number. The bar is drawn against this number. |

### App behavior

| Setting | What it does |
|---------|--------------|
| **Show notch panel** | On: the black area next to the notch (or at the top of the screen) with your numbers. Off: it disappears and the numbers move to the menu bar. |
| **Notify when Codex has 20%, 10%, or 0% left** | Sends a normal macOS notification when your ChatGPT (Codex) limit gets low. macOS asks your permission the first time. |
| **Launch at Login** | Opens Gauge automatically when you log in to your Mac. |
| **Auto-refresh** | How often Gauge reloads the numbers: every 1, 5, 10 or 15 minutes. 5 is a good choice. |

---

## 9. Understanding the numbers

- **Dollars are not a bill.** They are an estimate of what the same usage would cost at the normal public prices of Anthropic's service. If you use a subscription (Pro, Max, Team), you do not pay per token, so the dollar figure is just a way to compare days and projects. If your company pays by usage, it is a good guide, but your real invoice may be a little different because of discounts and extras.
- **Only this Mac is counted.** Using a website, a phone app or another computer does not appear in Gauge.
- **Limits are not published.** Claude does not tell programs how much of your limit is left, which is why the bar for Claude shows the time left in your session unless you type in the percentages. ChatGPT is different: its real limit comes straight from Codex.
- **Copilot is an estimate** unless you turn on the exact total. GitHub's own billing page is always the final word.

---

## 10. Something is not working

**I opened Gauge and nothing happens.**
Gauge has no window and no Dock icon. Look at the very top of the screen (see [section 4](#4-open-gauge-and-find-it-on-screen)). If you still do not see it, quit it with the steps in section 11 and open it again.

**macOS says Gauge "cannot be opened" or "cannot be verified".**
Follow the steps under *The first time you open it* in [section 3](#3-install-gauge).

**The card does not open when I move the mouse near the notch.**
Click the gauge icon in the menu bar instead; it always works. Some work-managed Macs restrict mouse tracking, and then only the icon works.

**The ChatGPT row says "Unavailable".**
Codex is probably not installed or not signed in. Follow [the ChatGPT steps](#chatgpt-codex-one-time-setup). Make sure you signed in with your ChatGPT account, not an API key.

**There is no Copilot row.**
It appears only after the Copilot command-line tool has been used on this Mac. If you only use Copilot in VS Code, turn on the exact total (see [section 6](#optional-exact-copilot-total-from-github)).

**The numbers are different from the website.**
Gauge counts only this Mac, and Claude and Copilot numbers are estimates (see [section 9](#9-understanding-the-numbers)).

**Claude shows `Idle` or an old number.**
Numbers refresh every few minutes. Click ⟳ on the card to refresh now.

**I turned on Launch at Login, but it does not start.**
Make sure Gauge is in the **Applications** folder, then switch the setting off and on again, or add it in **System Settings → General → Login Items** (see [section 5](#5-start-gauge-automatically-when-you-turn-on-your-mac)).

---

## 11. Quit and uninstall

**Quit Gauge:** click the ⏻ button on the card, or right-click the menu-bar icon → **Quit Gauge**, or press **⌘ Q** in that menu.

**Uninstall:**

1. Quit Gauge (above).
2. Open **Applications** and drag **Gauge** to the **Trash**.
3. If you switched on Launch at Login, also remove Gauge from **System Settings → General → Login Items**.

Gauge saves only your settings, in one small file on your Mac. Nothing else is left behind, and Gauge never changed your AI tools' files.

---

## 12. For developers

Gauge is native macOS (AppKit) with no third-party dependencies. It requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
swift run Gauge        # run directly
./build-app.sh         # builds dist/Gauge.app (universal) and dist/Gauge.zip
```

`build-app.sh` produces an ad-hoc-signed bundle. For Launch at Login and notifications, run the `.app` rather than `swift run`.

### Where the numbers come from

| Service | Source |
|---------|--------|
| Claude Code | local logs in `~/.claude/projects`, priced with Anthropic's public list prices |
| ChatGPT / Codex | `codex app-server` over local stdio for limits; `~/.codex/sessions` for per-project tokens |
| GitHub Copilot | `~/.copilot/session-state`; optionally `gh api` for billing |

Log readers are incremental: the first scan takes a few seconds, later refreshes take milliseconds. Adding a service means producing one `ProviderCard` in `AppModel.cards`; the card, the island and the menu bar pick it up.

### License and notices

- Released under the [MIT License](LICENSE). Contributions are welcome through issues and pull requests.
- Gauge is **not** an official Anthropic, OpenAI or GitHub product.
- The service logos come from [simple-icons](https://github.com/simple-icons/simple-icons) (CC0). They remain trademarks of their owners and are used only to tell the services apart.
