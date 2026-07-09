# Codex Light

macOS status bar app concept for viewing Codex usage limits through the official Codex/ChatGPT login flow.

## Documents

- [方案文档](docs/codex-light方案.md)
- [实现待办](PROJECT.md)

## Build

```bash
cd app/CodexLight
./package_app.sh
open "dist/Codex Light.app"
```

Release packaging and GitHub publishing are handled by the interactive script:

```bash
cd app/CodexLight
./release_app.sh
```

See [发布脚本说明](app/CodexLight/RELEASE.zh-CN.md).

If `swift build` asks for the Apple SDK license, run this once in Terminal:

```bash
sudo xcodebuild -license
```

## Current Flow

1. Click the menu bar summary.
2. Click the login/fetch icon or the refresh button.
3. The app starts the same OAuth PKCE flow used by Codex usage, opens the official OpenAI authorization page, and listens on `http://localhost:1455/auth/callback`.
4. After authorization, the app stores the OAuth token in Keychain and fetches Codex usage from `https://chatgpt.com/backend-api/wham/usage`.
5. Reset credits are fetched from `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`.
6. The latest successful snapshot is cached locally for fast menu bar startup.

## Product Goal

Show Codex short-window and weekly usage in the macOS menu bar, and provide a click-to-open detail panel with credits, reset coupons, expiration times, and the latest refresh status.

The app should use official OpenAI/Codex web login only. It should not store account passwords, bypass MFA, or depend on private account credentials.
