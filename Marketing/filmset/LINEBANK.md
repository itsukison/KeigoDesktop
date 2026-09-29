# LINEBANK.md — how a Gen Z line is funny, and the next ten

`scenarios.js` holds the ten lines that were shot. This file is why they were the wrong
*kind* of funny, the rule that replaces them, and the next batch. `FORMAT-TESTS.md` §4
(T2) asks for 50+ scenarios up front; this is where they accumulate.

---

## 1. The character is powerless, not defiant

Both reference lines are the same person:

> `shiiii twin ngl i have no idea what this means 💀`
> `lmaooo fam stop with the aura farming`

They are funny because the speaker is talking to a **Director of Marketing exactly the
way they talk to their best friend** — same warmth, same vocabulary, zero adjustment for
audience. The joke is **misjudged intimacy**, and the character is not rebelling. They
are simply incapable of code-switching and see nothing wrong with what they typed. That
is also the person the product saves, which is why this register sells and the other
one does not.

**The first ten drifted into a different character** — one who refuses, blames, keeps
score and defends themself: *that wasn't me, I sent it Tuesday* · *I'm logging off, I'll
do it Monday* · *own what, that's three jobs*. Those are **negotiating positions**, and a
negotiating position is neither funny nor powerless. It makes the speaker adversarial and
competent, and it quietly changes what the product is for: a tool that launders
insubordination is not the tool that saves someone who genuinely cannot code-switch.

### The three engines that are funny

| Engine | The move | Example |
|---|---|---|
| **Over-honest confession** | admits the thing a professional would hide | `lmaooo i completely forgot 😭` · `fam what is a QBR 😭` |
| **Misjudged intimacy** | teases the boss like a peer, affectionately | `lmaooo fam stop with the aura farming 😭` |
| **Absurd oversharing** | gives the real, far too personal reason | `twin i'm literally in the sea rn 😭` |

All three leave the speaker with no power. That is the load-bearing part.

### The test, three questions

1. **Would they send this exact text to their actual best friend?** If it is phrased
   *for* a boss — even rudely — it is the wrong character.
2. **Is the speaker powerless, or pushing back?** Confused, forgetful, over-honest,
   over-familiar, out of their depth, enthusiastic-but-clueless → funny. Refusing,
   accusing, scorekeeping, demanding, boundary-setting → mean, and mean is not the format.
3. **Strip test.** Delete every slang word and every emoji; what is left must still be a
   complete message. The product changes register, not content (see `README.md`).

Emotional register, in one line: **the speaker is losing and cheerful about it.**

### Vary the shape, not just the words

Batch one had a second tell: every line was `slang 😭 clause`, ten times, with the same
crying emoji in the same slot. That reads as a filled-in template, and a viewer who sees
three posts clocks it before they clock the joke. Nobody texts to a formula, so the batch
should not either.

What actually varies in real messages, and what batch two spreads across its ten:

- **Whether there is an emoji at all** — two lines have none, and they are not the weakest
- **Where it sits** — one opens on `☠️`, four end on one, two sit mid-line
- **Which one** — 🙏 💀 🥹 😭 ☠️ 😔 🫠, and `🥹🙏` doubled once. 😭 appears exactly once
- **Punctuation** — a full stop where a Gen Z line would not normally have one
  (`bro what. i genuinely don't know...`), a trailing `...`, a bare `??`
- **Caps** — `WAIT ME??`, `TODAY??`, `LMAOOO` as the whole reaction

Rule of thumb: if two consecutive lines in a batch have the same silhouette, rewrite one.

---

## 2. The next ten

Situations chosen so the honest answer is an admission rather than a defence. Each line
passes the strip test; the third column is roughly what the button should return, and is
what makes the gap visible.

| # | Setup — what the boss sent | Type this | Should come back as |
|---|---|---|---|
| 1 | double-clicking on levers, boiling the ocean | `bro what. i genuinely don't know what any of that means` | Apologies — I'm afraid I don't follow this. Would you mind explaining what you'd like me to look at? |
| 2 | how is the Harlow deck coming along? | `lmaooo i completely forgot can i get it to u friday 🙏` | Apologies, this had completely slipped my mind. Would Friday work for getting it over to you? |
| 3 | a long "bring your full self" paragraph | `lmaooo fam stop with the aura farming 💀 what do u need` | I appreciate the context, though I'd welcome something more direct — could you let me know exactly what you need from me? |
| 4 | quick one while you are off | `twin i'm literally in the sea rn can i send it monday 🥹🙏` | I'm away on leave at the moment — would it be alright if I sent this across on Monday? |
| 5 | walk the leadership team through this | `WAIT ME?? i've never done this before pls help 😭` | I'd be glad to, though I should flag that this would be my first time presenting — I'd be very grateful for some guidance. |
| 6 | own the client relationship on this one | `LMAOOO me?? idk what i'm doing but i'm down...` | I'm very happy to take this on, though I'll admit I'm not yet clear on everything it involves. |
| 7 | just checking this is still landing today | `☠️ wait it's due TODAY?? i thought friday, i'm on it` | Apologies — I had understood the deadline to be Friday. I'll get onto it right away. |
| 8 | you weren’t on the client call | `omg i'm so sorry i completely missed it catch me up? 😔` | I'm so sorry, I missed that entirely. Would you mind bringing me up to speed? |
| 9 | QBR deck to the PMO before SteerCo, flag RAG | `fam what is a QBR. i've been nodding for 3 weeks` | Apologies, could I ask what QBR refers to? I should have raised this sooner. |
| 10 | let’s circle back on this next week | `twin we've circled back 4 times 🫠 can we just decide today` | We've revisited this a few times now — would it be possible for us to reach a decision today? |

Line 3 is the one to shoot first. `aura farming` is the hardest thing on this list for the
model to carry across, and if the button handles it the prompt in §3 is working.

**Wired into `scenarios.js` as `e-011`…`e-020`**, on three new bosses — Tobias Renner,
Cecilia Vance, Nadia Okonjo. `./run.sh dark` loads this batch; batch one is untouched
behind `dark-b1`, because its E-2 twins have to reuse those exact lines.

---

## 3. The button prompt

Set this as the **prompt** of the button pressed on camera. Two notes before you do:

- **The button's title shows in the frame.** Call it something a real user would have —
  `Formal`, `Polish`, `Professional` — never anything that reads as a demo.
- **`user_prompts` is shared with the phone** (`AGENTS.md` §85), so this button appears on
  your iOS keyboard too. Add it as a new button rather than overwriting a builtin, and
  delete it after the shoot if you don't want it there.

It is written as a command instruction because that is what the backend applies to the
captured text, and per `AGENTS.md` §17 the button's instruction is the one the model
actually follows — it outranks the persona in the system prompt.

```
Rewrite this message into polished, professional business English, as if sending it to a
senior colleague on Slack.

Preserve the meaning exactly. Do not add facts, reasons, deadlines, apologies or offers
that are not already in the text, and do not drop any part of what is being said. A
question stays the same question; an admission stays the same admission; a request stays
the same request.

The input is casual Gen Z speech and will contain slang, abbreviations, internet
expressions and emoji. Read them for intent, not literally, and carry the intent across:

- filler and address words carry tone, not meaning, and are dropped: ngl, lowkey, fr, rn,
  no bc, i fear, twin, fam, bro, girl, unc, chat
- "no idea", "no clue", "lost" mean I do not understand
- "cooked" means in serious trouble, or badly flawed
- "yapping", "aura farming", "glazing" mean talking at length for effect instead of
  getting to the point
- "u, ur, tmr, idk, pls, tysm, ofc" mean you, your, tomorrow, I don't know, please, thank
  you, of course
- stretched letters and repeated punctuation (waitttt, ??) are emphasis, not content
- remove all emoji

Be warm and courteous, a little more formal than the situation strictly requires, but
never sarcastic and never so stiff that it reads as automated. Match the length of the
original: one short message in, one or two short sentences out.

Return only the rewritten message. No quotation marks, no preamble, no explanation.
```

**Check it against line 3 before filming ten takes.** If `aura farming` comes back
literally, or the rewrite invents a deadline nobody mentioned, the prompt needs another
pass — not the line.
