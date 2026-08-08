# KeigoDesktop

macOS companion to [敬語ボタン](https://github.com/itsukison) (AIキーボード) — the same account, the same rewrite buttons, a different surface.

A small pill sits at the bottom of the screen above the Dock. Hover to expand your configured buttons, press one to rewrite the text you're editing in any app, and insert the result in place. No keyboard, no IME — macOS already has a Japanese input method.

## Features

- **Hover bar** — your `user_prompts` buttons from the phone, plus a custom free-text input
- **Accessibility-first I/O** — reads and writes via AX; clipboard fallback when needed
- **Reply mode** — copy a message, hover the bar, describe how you want to answer
- **Settings window** — edit buttons, view local history and stats, manage account
- **Shared backend** — Supabase auth, `user_prompts`, and billing with the iOS app

## Requirements

- macOS 14.0 or later
- Xcode 15+ with XcodeGen (`brew install xcodegen`)
- Accessibility permission (prompted on first launch)

## Build

```bash
# Generate the Xcode project (after changing project.yml or adding files)
xcodegen generate

# Build and run
xcodebuild -scheme KeigoButtonMac -configuration Debug build

# Unit tests (AppKit-free core)
swift test
```

Open `KeigoButtonMac.xcodeproj` in Xcode to run the app. The app uses `.accessory` activation policy — no Dock icon; reach the settings window from the menu-bar item.

Grant **Accessibility** in System Settings when prompted. Dev rebuilds change the binary identity and usually require re-granting the permission.

## Project layout

```
App/           SwiftUI + AppKit — overlay bar, main window, onboarding
Sources/       Testable core (no AppKit)
  DesktopRewriteKit/   Models, auth, rewrite service, prompts, history
  TextIO/              AX + clipboard capture/replace
Tests/         Unit tests for the core packages
supabase/      desktop-rewrite Edge Function and desktop schema migrations
docs/          Design reference (design.md), pricing notes, todos
reference/     Visual reference screenshots
scripts/       Diagnostics (e.g. axdiag.swift for AX debugging)
```

Generated artifacts (`.build/`, `*.xcodeproj/`) are gitignored; run `xcodegen generate` after clone.

## Architecture notes

- **No App Sandbox** — required for cross-process Accessibility; distribution is Developer ID + notarization, not Mac App Store
- **No provider API keys in the bundle** — all AI calls go through the `desktop-rewrite` Edge Function with the user's JWT
- **Separate desktop schema** — `desktop.rewrite_events`, usage buckets, and activations; does not touch the keyboard's tables
- **`user_prompts` is shared** — button edits on Mac sync to the phone and vice versa

For full architectural detail, state machines, and implementation constraints, see [AGENTS.md](AGENTS.md).

## Related

- iOS keyboard app: sibling repo (`Japanese` / KeigoButton)
- Landing page: lives in `landing/` locally but is not part of this repository

## License

Private — all rights reserved unless otherwise noted. Reicon Outline icons in `App/Resources/Icons.xcassets` are MIT (see catalog README).
