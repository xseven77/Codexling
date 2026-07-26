# Codexling Project

## Current Status

Codexling is a native Swift/SwiftUI macOS app. It is no longer an initial shell or folder-layout proposal.

Implemented:

1. A custom `NSStatusItem` capsule showing Codex task state and quota health.
2. OpenAI OAuth PKCE through the system browser and the local `http://localhost:1455/auth/callback`.
3. Codex quota, reset-credit, and best-effort ChatGPT subscription-period reads.
4. A detached companion dashboard with task activity, selected Pet animation, daily companion time, quota cards, and settings.
5. Read-only local Codex activity discovery from the thread index and rollout JSONL.
6. Built-in and custom Pet discovery, Codexling Pet installation, and two-way Pet selection sync with Codex.
7. Configurable automatic refresh, local snapshot caching, update checks, and optional always-on-top window behavior.
8. Ad-hoc signed `.app`, `.zip`, and `.dmg` packaging plus an interactive GitHub Release script.

The distributed build is currently ad-hoc signed and is **not notarized**.

## Current Folder Layout

```text
Codexling/
├── README.md
├── PROJECT.md
├── docs/
├── app/
│   ├── Codexling/
│   │   ├── Package.swift
│   │   ├── Resources/
│   │   ├── Sources/Codexling/
│   │   ├── Tests/CodexlingTests/
│   │   ├── package_app.sh
│   │   └── release_app.sh
│   └── landing/
└── docker/landing/
```

## Technical Boundaries

- Use Swift + SwiftUI with AppKit where macOS status-item and window behavior requires it.
- Keep the non-public ChatGPT `wham` and `subscriptions` endpoints isolated in `CodexUsageService` and `CodexlingParser`.
- Store OAuth tokens in `~/Library/Application Support/Codexling/oauth_token.json` with mode `0600`; migrate and remove legacy Keychain entries when found.
- Store the last successful quota snapshot and companion statistics in Application Support.
- Read Codex SQLite/JSONL and Pet configuration locally and read-only, except when the user explicitly selects or installs a Pet.
- Never request account passwords, browser cookies, or MFA codes. The local activity parser reads rollout JSONL only to derive task state and a truncated visible summary; it does not persist, upload, or render model reasoning, raw tool arguments, complete prompts, tokens, or environment variables.

## Release Boundary

`package_app.sh` produces ad-hoc signed local artifacts. `release_app.sh` validates the workspace and GitHub authentication, updates the version, packages and verifies the DMG, commits the version when needed, pushes the branch/tag, and creates or updates the GitHub Release.

Apple Developer ID signing and notarization remain future release-hardening work.
