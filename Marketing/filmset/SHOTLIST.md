# SHOTLIST.md — batch two, ten English E-1 takes

Read `README.md` once for the set and `LINEBANK.md` §1 for the register, then film off
this page. Ten takes, one variant (`en-genz-e1`), dark theme on all ten.

**This is batch two (`e-011`…`e-020`).** Batch one was filmed 2026-08-22 and is still in
`scenarios.js` — `./run.sh dark-b1` brings it back, unchanged, because its E-2 twins have
to reuse those exact lines. Nothing here interleaves with it. Strategy is `GTM.md` §4.5; the test is
`FORMAT-TESTS.md` §4 (T2). Lines and threads live in `scenarios.js` — this file is
just the order to shoot them in and what has to be true in every take.

```
./run.sh dark                    batch two, dark, empty composer
./run.sh dark-guide              …plus the 9:16 crop guide, for framing
./run.sh dark-genz               …with the line already typed, to focus and frame on
./run.sh dark-nosb-fill=.55      sidebar hidden, smaller window — if the display fills the frame
./run.sh dark-b1                 batch one, as shot
./run.sh dark-all                all twenty, in order
```

`⌥→` next scenario · `⌥←` back · `⌥1`–`⌥9` jump within the loaded batch (**the tenth is
`⌥→` from the ninth**)
· `⌥C` clear · `⌥K` theme · `⌥S` sidebar · `⌥G` crop guide · `⌥H` HUD (**never film with
it on**).

## Before the first take

0. **Set the button.** `LINEBANK.md` §3 has the prompt to paste into it, and the two
   things to know first: the button's title is in frame, and `user_prompts` is shared with
   your phone. Test it on one line before committing to a batch of takes.
1. `swiftc -O ../../scripts/axdiag.swift -o /tmp/axdiag && /tmp/axdiag` with the caret in
   the composer. If the write does not land, the shoot is dead — fix it before take one,
   because the same path serves Gmail, Notion and web Slack.
2. Hide the macOS menu bar (System Settings → Control Centre → Automatically hide and
   show the menu bar → Always).
3. `⌥G`, frame so the boss's last message **and** the composer are both inside the guide,
   then turn it off.
4. Read the line from where the phone sits. If it needs a second look, swap in an `alt`.

## Every take, same five beats

1. Thread on screen, boss's message visible, composer empty.
2. Type the Gen Z line by hand. Enter and Tab are swallowed, so nothing can send.
3. One beat of regret — no cut, no zoom.
4. **Select nothing.** Caret in the field is enough: with an empty selection the app
   captures the whole field (`AGENTS.md` §5, `.wholeInput`). Hover the pill, press the
   button.
5. Hold on the rewritten text long enough to read the first line.

**The rewrite must come from the app, on camera.** The `corporate` field in
`scenarios.js` is a latency fallback only — after each take, paste what the product
actually returned back into that field so the fallback stays honest.

**No product beat, no post.** The organic cut (type, delete, retype) is allowed as at
most one control post, never as the format.

## The ten

Cast rotates so the frame never repeats twice running. `⌥n` is the jump key.

| ⌥n | id | Boss | The message you are answering | Type this |
|---|---|---|---|---|
| 1 | `e-011` | Tobias · Head of Growth | double-clicking on levers, boiling the ocean | `bro what. i genuinely don't know what any of that means` |
| 2 | `e-012` | Cecilia · Client Partner | how is the Harlow deck coming along? | `lmaooo i completely forgot can i get it to u friday 🙏` |
| 3 | `e-013` | Nadia · Programme Lead | a long "bring your full self" paragraph | `lmaooo fam stop with the aura farming 💀 what do u need` |
| 4 | `e-014` | Tobias · Head of Growth | quick one while you are off | `twin i'm literally in the sea rn can i send it monday 🥹🙏` |
| 5 | `e-015` | Cecilia · Client Partner | walk the leadership team through this | `WAIT ME?? i've never done this before pls help 😭` |
| 6 | `e-016` | Nadia · Programme Lead | own the client relationship on this one | `LMAOOO me?? idk what i'm doing but i'm down...` |
| 7 | `e-017` | Tobias · Head of Growth | just checking this is still landing today | `☠️ wait it's due TODAY?? i thought friday, i'm on it` |
| 8 | `e-018` | Cecilia · Client Partner | you weren’t on the client call | `omg i'm so sorry i completely missed it catch me up? 😔` |
| 9 | `e-019` | Nadia · Programme Lead | QBR deck to the PMO before SteerCo, flag RAG | `fam what is a QBR. i've been nodding for 3 weeks` |
| `→` | `e-020` | Tobias · Head of Growth | let’s circle back on this next week | `twin we've circled back 4 times 🫠 can we just decide today` |

Each row has three `alts` in `scenarios.js` at the same length. Swap one in if a line
reads badly on camera — **do not grow the line**; twelve words is the ceiling.

**Why every line has a plain second half.** The app makes a message polite; it does not
invent a message that was never there. `unc it's 10pm 💀 be so fr rn` cannot become
"I'll prioritise it in the morning", because nothing in it says that. So each line is
slang reaction **+ the actual thing being said**, and it has to pass one test:

> delete every slang word and every emoji — what is left must still be a complete message.

If you improvise a line on camera, run that test on it first. Same rule binds the
rewrite: every fact in the polite version has to come from what you typed, never from
the boss's message on screen.

**And keep the character powerless** — confused, forgetful, over-familiar, out of their
depth. An improvised line that refuses or blames is the wrong character even if the slang
is perfect. `LINEBANK.md` §1.

## What not to change mid-sample

One variable per variant (`FORMAT-TESTS.md` §5), and for these ten the variable is the
line. So: dark theme on all ten, same `--fill` and framing, same audio, same POV on
screen (`pov: you're a 22 year old working in corporate`), same CTA and link in every
caption. Anything else moving makes the ten posts unreadable as one sample.

Keep every take. When the E-2 clips are ready, the twins have to reuse these exact ten
lines, POVs and captions — that is the only thing that makes the pair readable.
