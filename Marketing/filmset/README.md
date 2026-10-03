# filmset — the Slack film set for Format E

## Japanese: controlled KeigoButton overlay

`slack-ja.html` now includes a stationary browser reconstruction of KeigoButton.
All 12 Japanese scripts use the authored outputs in `scenarios-ja.js`; no model,
account, API, or real app is needed. These are scripted demonstrations, not recorded
model responses. This workflow supersedes the live-generation/fallback instructions
below for the Japanese set. English stays in its original live-app mode by default;
add `overlay` to its hash to opt into the same reconstruction.

Japanese framing fills the full viewport, with the entire overlay
enlarged to 150% for small-monitor demos. Override with `fill=.8` and
`buttonscale=1` for shorter framing and native button size; button scale
accepts values from 1 to 2. Composer/result widths are capped to the viewport.

The overlay uses the current native proportions, Inter font, actual mascot
animation atlases at 4 fps, and native macOS SF Symbol renders. CSS approximates the
AppKit smoked-glass backdrop; it does not use a screenshot as an interactive control.
Its fixed bottom-center anchor is 6 px above the viewport edge. It is not draggable.
The four saved-button labels match `bar_jap.png`. Outputs are fixed per scenario,
regardless of which saved button or custom guidance is used; use 敬語 or Reply for
these takes. Regenerate replays the same output and adds a result page.

```sh
./run.sh ja dark                       # first take, empty Slack composer
./run.sh ja dark+scenario=4+genz        # take 4, input preloaded for framing
./run.sh ja dark+scenario=10            # take 10, copy the received message first
./run.sh ja dark+scenario=10+intent     # take 10, Reply intent preloaded
./run.sh ja dark+scenario=10+result     # result card for framing
./run.sh ja dark+delay=1800             # fixed 1.8 s generating animation (default 1.1 s)
./run.sh ja dark+overlay=off            # use the real native app instead
```

- **敬語:** type the scenario's casual line in Slack → hover the mascot → 敬語 →
  result → 挿入 (or Enter). The result replaces the draft or selected range.
- **Reply:** select the boss's message → ⌘C → click the empty Slack composer →
  hover → 返信 → type the short intent → Enter → 挿入. Copy reveals Reply and its ×;
  selecting without copying does not. The original received message remains intact.
- **Escape** closes the instruction/result surface or cancels generation. Clicking
  outside the instruction composer cancels it. Hover collapses after 300 ms.
- **⌥I** preloads the current take: Slack text for 1–6, attached source plus Reply
  intent for 7–12. **⌥R** arms the last received message for framing without copying.
  **⌥C** resets the take. **⌥→ / ⌥←** reach all 12; **⌥1–9** jump to the first nine.
  The POV hook and scenario number appear only in the optional **⌥H** HUD.
- Snooze or quit the real native app before filming the reconstruction to avoid two
  bars. Hide the filming HUD and crop guide before rolling.

| Take | Feature | Hook |
|---|---|---|
| 1 | 敬語 | 社会人1年目、いきなりラスボス |
| 2 | 敬語 | 上司にだけ正直すぎる新卒 |
| 3 | 敬語 | 3週間、意味も分からずうなずいてた |
| 4 | 敬語 | 「最終版」なのはファイル名だけ |
| 5 | 敬語 | 勢いで「できます」って言った新卒 |
| 6 | 敬語 | 部長を完全に友達だと思ってる |
| 7 | Reply | 17:59に「今日中」って言う上司 |
| 8 | Reply | 有休を成長イベントに変えてくる上司 |
| 9 | Reply | 上司の指示、矛盾してて詰んだ |
| 10 | Reply | 会社のSlackをマッチングアプリだと思ってる上司 |
| 11 | Reply | 業務連絡より服装チェックが多い上司 |
| 12 | Reply | なぜか休日の写真を欲しがる上司 |

## Original live-app filming workflow

The mockup that gets **filmed**, not rendered. `GTM.md` §4.5 is the format;
`FORMAT-TESTS.md` §4 (T2) is the test it feeds. This is a live page with a **real
editable composer**, because the joke in Format E is the typing: an unhinged message
finishes typing, gets regretted, and comes back corporate.

Do not confuse it with `Raylight/mockups-en/` — those are fixed 1468×1080 plates shot
headless for the launch video, and their sizing is load-bearing for Raylight's own
transforms. This is a copy of that chrome rebuilt to fill a display and to be typed in.

**Two sets, one chrome.** `slack.html` (English, `scenarios.js`) and `slack-ja.html`
(日本語, `scenarios-ja.js`) are siblings: same window, same knobs, same keys. Only the
language, the type stack and the scenario source differ — **a fix to the chrome has to be
made in both files.**

```
./run.sh              # fullscreen, no address bar, throwaway Chrome profile
./run.sh genz         # the line already in the box, for framing the shot
./run.sh dark-guide   # dark Slack + the 9:16 crop guide
./run.sh ja           # the Japanese set
./run.sh ja genz      # …with the line loaded
./run.sh genz+fill=.7 # same, with a bigger window
```

## Size and position

A 27"+ desk display is far larger than the frame a phone keeps, so the mockup is drawn
as a **small window parked bottom-centre** — where the pill lives — with free space
above and to the sides. Two knobs at the top of `slack.html`:

| Knob | Default | What it does |
|---|---|---|
| `--fill` | `.80` | Window height as a fraction of the display. Everything is a multiple of `--u`, which derives from it, so changing it rescales chrome, icons and type **together** — the ratio never changes |
| `--lift` | `0px` | Space below the window. `0` parks it flush on the bottom edge, where the pill sits. Raising it also wants `--radius` switched to all four corners |

Override without editing the file: `./run.sh fill=.42`, or `slack.html#fill=.42`.

**What the crop guide shows at the default.** A 9:16 slice of the display is
`0.5625 × height` wide; the window is `1.36 × height × --fill`, so at `.80` it is about
1.9× the width of a full-height portrait crop — the sidebar and some of the message pane
fall outside it. That is fine if the phone frames the monitor plus some desk, and not
fine if the screen fills the frame; for the latter, `--fill ≈ .40` fits the whole window
and `≈ .55` fits it with the sidebar hidden (`⌥S`). Check with `⌥G` before rolling, then
turn it off.

## Keys

**Typing is yours.** The composer is a normal editable field — type the Gen Z line and
delete it by hand on camera; nothing here animates or drives it. Two interventions only:

- **Enter and Tab are swallowed**, so a real key never "sends" the message or tabs out
  of the field mid-take.
- **Set-up commands all sit behind `⌥`**, which cannot be hit by accident while typing.
  Nothing sits behind `⌘` — **⌘A / ⌘C / ⌘V are the product's own path into this field**
  (`AGENTS.md` §5: a browser is read via AX and written via a synthesized ⌘V).

| Key | Does |
|---|---|
| `⌥→` `⌥←` | next / previous scenario |
| `⌥1`–`⌥9` | jump to scenario n |
| `⌥C` | clear the composer |
| `⌥K` | dark Slack. A bright monitor is the worst thing to point a phone at — test both |
| `⌥S` | hide the sidebar, for tighter portrait crops |
| `⌥G` | 9:16 crop guide — what a portrait phone frame will actually keep |
| `⌥H` | HUD (scenario id, situation). Off by default. **Never film with it on** |
| `⌥F` | browser fullscreen, if `run.sh` was not used |

Loading `./run.sh genz` puts the line in the box already typed — useful for framing and
focusing the shot before rolling, and as the starting state for a take that opens on the
message and deletes it.

## Scenarios

`scenarios.js` — one object per scenario, columns matching the content engine in
`FORMAT-TESTS.md` §4. Add to the array; no build step, just reload.

- `genz` — the whole post lives or dies here. Write what a 21-year-old would text their
  closest friend. If it reads as deliberately written to be funny, rewrite it. **The
  character is powerless, not defiant** — confused, forgetful, over-familiar, out of their
  depth. A line that refuses, blames or keeps score is the wrong character however good
  the slang is; `LINEBANK.md` §1 has the test and the reasoning. **Keep it under twelve
  words** — the viewer has to clock it, laugh, and still be there for the
  button press. `alts` holds the other lines written for that situation; swap one in
  rather than lengthening the primary.
- **The line has to be translatable, and this is the constraint that kills drafts.** The
  product changes register, not content: it makes a message polite, it cannot infer a
  message that was never there. So a line is slang reaction **plus the actual thing being
  said**, and it passes one test — *delete every slang word and every emoji; what is left
  must still be a complete message.* `unc it's 10pm 💀 be so fr rn` fails (strip it and
  nothing remains, so no rewrite can promise the work by morning);
  `unc it's 10pm 💀 i'll do it first thing tmr` passes. The same rule binds `corporate`:
  every fact in the rewrite comes from the line, never from the boss's message.
- `cast` / `trigger` — the scrollback and the boss identity are shared objects at the top
  of the file; a scenario names a cast and supplies only the message that sets up its own
  joke. Rotating the cast is what keeps a repeat viewer from recognising the frame: at the
  default `--fill` the sidebar is outside the 9:16 crop, so the boss's name, their avatar
  and their last message are the only things repeatedly on screen.
- **`⌥1`–`⌥9` only reaches nine.** The tenth scenario is `⌥→` from the ninth.
- **The Japanese set is not a translation.** English is slang-in-Outlook; Japanese is
  **タメ口 → 敬語** — a 部長 addressed with no 敬語 at all, which is a sharper taboo and
  needs no slang to land. `scenarios-ja.js` carries the reasoning.
- `corporate` — **the real app produces this on camera.** The field and the `#corp`
  hash token (there is no `R` key) are a latency fallback, and what they show must be
  text KeigoButton actually returned, pasted back in. Never a hand-written line
  presented as product output.
- `thread` — keep it full enough that the message pane has no empty band at the top; a
  portrait crop of a half-empty Slack is a white rectangle.

## If the pill says there is no text

That message is `TextIOError.noTarget` — the app found nothing to rewrite. Three causes,
in the order worth checking:

1. **The composer was empty.** A saved button needs text; the app is right to refuse.
   Type the line first, or use ✎.
2. **The field is not a real text control.** This is why the composer is a native
   `<textarea>` and not a `contenteditable` div like Slack's own: a contenteditable root
   keeps its text in child nodes, so `kAXValue` can answer empty and capture is rejected
   over a field that visibly has text. If you ever swap it back, expect this failure.
3. **Chrome was not primed.** Chromium exposes no focused element until
   `AXManualAccessibility` is set on its application element. The app does this off the
   frontmost pid before its first read, so this should be handled — but it is the thing
   to confirm rather than assume.

The decisive check, with the caret in the composer:

```
swiftc -O ../../scripts/axdiag.swift -o /tmp/axdiag
/tmp/axdiag            # inspect only; --write also attempts the real write
```

It prints the focused element's role, whether `kAXValue` / `kAXSelectedText` read, and
whether they are settable. A nil focused element points at cause 3; a focused element
with an empty `kAXValue` over visible text points at cause 2. The app logs the same
verdict — `capture rejected role=… hasValue=… isField=…` on subsystem
`com.core7.keigobutton.mac`.

**If axdiag says the field reads fine and the pill still refuses, it is the app, not the
mockup** — and worth fixing before the shoot, because the same path serves Gmail, Notion
and web Slack.

## Before the first shoot

1. **Run `scripts/axdiag.swift` against the composer** with the page focused. Chrome
   returns `nil` for `kAXFocusedUIElement` until `AXManualAccessibility` is primed — that
   path is hardened, but confirm the write lands before writing 50 scenarios against it.
   If it fails, Safari is the fallback target.
2. **Hide the macOS menu bar** (System Settings → Control Centre → Automatically hide
   and show the menu bar → Always). A menu bar with your own apps in it is the second
   thing that gives the mockup away.
3. **Frame with `G` on, then turn it off.** The guide shows the 9:16 slice a portrait
   phone keeps; the boss's message and the composer both have to live inside it.
4. **Check the Gen Z line is readable** in that crop from where the phone will sit. It is
   the joke — if it needs a pause to read, the post is already lost.
5. Keep the workspace generic. `Meridian Group` and a plain sidebar are enough; there is
   no reason to put a Slack wordmark in frame or imply a partnership.
