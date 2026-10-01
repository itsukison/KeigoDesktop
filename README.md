# KeigoButton for Mac

The iPhone version of KeigoButton started with a simple idea: rewriting a message should happen where you are already typing.

The Mac version asks the same question at a larger scale: **what if every text field on your computer could act like an AI input field?**

Instead of opening a separate chatbot, copying context, writing a prompt, and pasting the answer back, KeigoButton sits quietly near the bottom of the screen. Hover over it, choose a saved instruction or write a one-off request, and it works against the text field you were already using.

**Product:** https://keigobutton.com/

## Why I built it

After shipping the iOS keyboard, I noticed that the underlying problem was not really “people need a keigo button.”

The repeated behavior was closer to:

1. receive some context,
2. know roughly what you want to say,
3. ask an LLM to turn that intent into the final message.

On desktop, that workflow happens across Slack, Gmail, LinkedIn, browsers, native apps, and Electron apps. The interesting problem became figuring out how much of that context and text interaction could be handled without forcing the user into another interface.

That is what this repo explores.

## How it works

KeigoButton is a native macOS app built with SwiftUI and AppKit.

A small hover bar stays above the Dock. From there you can:

- run one of your saved rewrite buttons,
- enter a free-form instruction,
- rewrite selected text or the current input,
- use copied text as explicit reply context,
- review the result before inserting it,
- sync your account and saved buttons with the rest of KeigoButton.

The main challenge is not generating text. It is reliably interacting with whatever app currently owns the text field.

## The interesting engineering problem: text I/O

The primary path uses the macOS Accessibility API.

```text
focused app
   ↓
AXUIElement
   ↓
capture text / selection / cursor context
   ↓
rewrite service
   ↓
write result back into the original field
```

When Accessibility cannot safely handle a field, the app has a clipboard-based fallback.

This sounds straightforward until you deal with real applications. Native AppKit fields, Chrome, Electron apps, Slack, Gmail, and custom editors all expose slightly different accessibility behavior. Focus is also fragile: if the overlay becomes the key window too early, the original field can stop being the focused target.

A lot of this project is therefore about **context acquisition, focus management, and graceful fallback**, not the LLM call itself.

## Architecture

```text
App/
├── Overlay/              # hover bar, generating state, result panel
├── Main/                 # settings and account UI
├── Design/               # shared native design system
└── Resources/

Sources/
├── DesktopRewriteKit/    # auth, prompts, rewrite service, local history
└── TextIO/               # Accessibility + clipboard capture/replace

Tests/
├── DesktopRewriteKitTests/
└── TextIOTests/

supabase/
└── functions/
    └── desktop-rewrite/  # authenticated rewrite endpoint
```

The testable core deliberately avoids AppKit where possible. That makes the capture/replacement logic easier to test independently from the window system.

## A few decisions I care about

### Don't steal focus

The floating pill should never become the key window just because the user hovered over it. The original app needs to stay focused long enough for us to capture the correct text target.

### Accessibility first, clipboard second

The Accessibility API gives a much cleaner experience when an app exposes the right attributes. Clipboard interaction is kept as a fallback rather than the default.

### Keep credentials off-device

Provider API keys are not bundled in the Mac app. Rewrite requests go through an authenticated backend.

### Share the product, not every implementation detail

The Mac and iOS apps use the same account and product concepts, but desktop-specific usage and rewrite data live separately. The two surfaces have very different constraints.

## Run locally

Requirements:

- macOS 14+
- Xcode 15+
- XcodeGen
- Accessibility permission

```bash
brew install xcodegen
xcodegen generate
open KeigoButtonMac.xcodeproj
```

Run the testable Swift packages with:

```bash
swift test
```

Because development rebuilds change the binary identity, macOS may ask you to grant Accessibility permission again after rebuilding.

## More detail

This README is intentionally the short version. The repo contains much deeper notes from building and testing the app:

- [AGENTS.md](./AGENTS.md) — current architecture and implementation constraints
- [design.md](./design.md) — visual direction
- [docs/](./docs/) — investigations and supporting technical notes
- [scripts/](./scripts/) — diagnostics for Accessibility and text I/O

---

What I like about this project is that the hard part sits outside the model. The LLM can already write a good reply. The product problem is making that capability available with almost no ceremony, inside software that was never designed for it.
