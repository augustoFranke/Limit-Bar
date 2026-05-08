# Limit Bar

Native macOS menu-bar app for monitoring usage limits across multiple AI providers. It currently supports isolated ChatGPT/Codex accounts and Claude usage via the local Claude Code CLI login — no cookies, session keys, or API keys to paste.

## How It Works

- The app stores provider account slots under Limit Bar's Application Support data.
- Codex accounts get isolated Codex profiles, one per added account, and each profile runs its own `codex app-server` process.
- Codex login uses Codex's official `account/login/start` flow and opens the returned ChatGPT/Codex login URL in your browser.
- Codex rate limits are read through Codex's `account/rateLimits/read` account surface, the same structured quota data Codex exposes to native clients.
- Codex auth is configured with isolated per-account Codex auth files under Application Support, so Limit Bar is not coupled to the main Codex app login/logout state.
- Claude accounts reuse the OAuth token written by Claude Code on `claude login`, so there is no extra credential to copy or paste.

## Claude Account Setup (Automatic)

If you have Claude Code installed and logged in, Limit Bar picks up your account automatically:

1. Install Claude Code from [claude.com/claude-code](https://claude.com/claude-code).
2. Run `claude login` once and complete the browser sign-in.
3. Open Limit Bar and click **Add Claude Account**.

That's it. Limit Bar reads the Claude Code OAuth token from `~/.claude/.credentials.json` (with a fallback to the `Claude Code-credentials` system Keychain item) and pulls your 5-hour and weekly usage from the Claude API's unified rate-limit response headers. If the credentials are missing or expired, the slot enters the "Login required" state — run `claude login` again and click **Log in** in the menu to retry.

## Build and Run

```bash
make run
```

Codex accounts require the Codex CLI at `/opt/homebrew/bin/codex` or `/usr/local/bin/codex`.
