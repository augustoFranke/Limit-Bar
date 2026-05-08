# Limit Bar

Native macOS menu-bar app for monitoring AI usage limits across multiple accounts. Supports isolated Codex (ChatGPT) accounts and Claude Code — no cookies, session keys, or API keys to paste.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

## Features

- **Multiple Codex accounts** — add as many isolated Codex accounts as you need; each gets its own profile and `codex app-server` process.
- **Claude Code** — automatically picks up the OAuth token written by `claude login`; no extra setup.
- **Live usage bars** — 5-hour and weekly limit windows with percentage used, colour-coded by pressure (green → orange → red).
- **Reset notifications** — schedules a system notification for each window reset so you know when limits clear.
- **Auto-refresh** — polls every minute and force-refreshes on wake from sleep; manual refresh button always available.
- **Last-known limits** — if a session expires, the last-known usage is shown dimmed with a "Login required" banner so you still have context while re-authenticating.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (for building from source)
- [Codex CLI](https://github.com/openai/codex) at `/opt/homebrew/bin/codex` or `/usr/local/bin/codex` (for Codex accounts)
- [Claude Code CLI](https://claude.ai/claude-code) with an active `claude login` session (for Claude accounts)

## How It Works

### Codex

Each Codex account slot runs an isolated `codex app-server` process backed by its own credential directory under `~/Library/Application Support/LimitBar/accounts/account-N/`. This keeps Limit Bar's login state completely separate from any global Codex installation. Login uses Codex's `account/login/start` JSON-RPC method, which opens a ChatGPT/Codex sign-in URL in your browser. Limits are read via `account/rateLimits/read` — the same structured quota data Codex exposes to native clients.

### Claude

Limit Bar reads the OAuth token written by the Claude Code CLI to `~/.claude/.credentials.json` (with a fallback to the `Claude Code-credentials` system Keychain item). It sends a minimal 1-token request to the Claude API and reads your 5-hour and weekly utilisation directly from the `anthropic-ratelimit-unified-*` response headers — no usage data is stored or transmitted elsewhere.

## Claude Account Setup

1. Install Claude Code from [claude.ai/claude-code](https://claude.ai/claude-code).
2. Run `claude login` once and complete the browser sign-in.
3. Open Limit Bar and click **Add Claude Account**.

If credentials expire, the slot shows "Login required" with last-known limits dimmed. Run `claude login` again and click **Log in** in the menu to refresh.

## Build and Run

```bash
# Build the .app bundle and open it
make run

# Build only
make app

# Debug build via Swift Package Manager
swift build

# Run tests
swift test

# Remove all build artifacts
make clean
```

The compiled app bundle is placed at `build/Limit Bar.app`. To install, copy it to `/Applications`.
