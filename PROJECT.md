# Codexling Project

## Milestones

1. Create a SwiftUI macOS menu bar shell with `MenuBarExtra`.
2. Add Codex usage-style OAuth PKCE login through the official OpenAI authorization page.
3. Exchange OAuth code locally through `http://localhost:1455/auth/callback`.
4. Fetch Codex usage from ChatGPT `wham` endpoints and parse quota payloads.
5. Render menu bar summary and detail popover.
6. Cache the latest successful snapshot locally.
7. Add refresh scheduling, login-expired handling, and parser failure states.
8. Package as a notarizable macOS app.

## Initial Folder Layout

```text
Codexling/
  README.md
  PROJECT.md
  docs/
    codexling方案.md
  app/
    # SwiftUI app source will live here
  adapters/
    # Page/API adapter notes and test fixtures will live here
```

## Technical Bias

- Prefer Swift + SwiftUI for the native menu bar app.
- Use the OAuth PKCE + `wham` API approach from Codex usage.
- Store OAuth tokens in Keychain. Do not store passwords.
- Keep quota parsing isolated so endpoint payload changes can be handled in one place.
