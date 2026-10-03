# How the Mac app is doing — plain-English read of PostHog

Date: 2026-08-28 (JST) · Project 549465 `KeigoButton Desktop (macOS)` · Data since 2026-08-09

**How this was counted.** Everything below excludes two accounts: `itsukison00@gmail.com`
(the owner) and `keigobutton@gmail.com` (team). Those two are most of the traffic and would
make the product look far healthier than it is. Everything is filtered to `surface = macos`,
so the 198 leaked keyboard events from 2026-08-23 are not in any number here.

"Real rewrite" means a finished rewrite in some **other** app — not the built-in tutorial.
The tutorial rewrites the app's own text box, so it reports our own bundle id, and that is
how the two are told apart.

---

## 【結論】

Roughly 21 outside people have tried the app in three weeks. **Only 7 of them ever used it
for real work**, and only 5 came back and used it for real on more than one day. Most people
finish the tutorial and then stop. When people do use it for real, they are almost always
rewriting a chat message (LINE, Teams, Chatwork, Slack) with a saved button — the
"natural Japanese" button above all. The single biggest technical problem is that the app
**cannot read the text** on about a third of attempts. Nobody has paid yet.

---

## 【論点・根拠】

### 1. How many people, and where from

| Thing | Number |
|---|---|
| Installs | 25 installs by 22 people |
| People in the project (all time) | 23 (2 are owner/team → **21 outside users**) |
| Signed up | 13 people |
| Finished onboarding | 16 people |
| First data | 2026-08-09 |

Where people say they heard about it (12 answered):

| Source | People |
|---|---|
| TikTok | 7 |
| Friend | 2 |
| Instagram | 2 |
| X | 1 |

TikTok is doing the work. Nothing else is meaningfully feeding installs yet.

### 2. Do they actually use it? Mostly no

Of the 21 outside users:

- **7 people (33%)** ever completed a rewrite in a real app.
- **14 people (67%)** never got past the tutorial — they installed, did the practice, and
  that was the end of it.
- Together those 7 people produced **40 real rewrites** in three weeks.

The event totals show the same story:

| Event (outside users only) | In the tutorial | In real apps |
|---|---|---|
| Rewrite finished | 56 | 40 |
| Result put into the app | 47 | 14 |
| Rewrite failed | 0 | 32 |

Read the middle row carefully. **Of 40 real rewrites, only 14 results were actually inserted
back into the text box** — about 35%. Zero were copied. So even among the people who use it,
roughly two out of three real rewrites are generated and then thrown away. Inside the
tutorial the insert rate is 47/56 (84%), because the tutorial only ends when you press
Insert. The gap between 84% and 35% is the honest measure of the product's problem.

### 3. Are people coming back? Half open it again, a quarter actually use it again

| Question | People | Share |
|---|---|---|
| Opened the app again on a later day | 10 of 21 | 48% |
| Did a **real** rewrite on 2+ separate days | 5 of 21 | 24% |
| Only ever seen on one single day | 11 of 21 | 52% |

The five repeat users, by how much they did:

| User | Real rewrites | Days with a real rewrite | Span |
|---|---|---|---|
| sahildhapola7505 | 11 | 4 | 8/24 – 8/27 |
| shionpark06 | 9 | 2 | 8/12 – 8/27 |
| kentaromoriya19 | 7 | 3 | 8/25 – 8/28 |
| natsuki.kataoka.2000 | 4 | 2 | 8/23 – 8/25 |
| dai600417 | 4 | 2 | 8/21 – 8/23 |

Two more (takuto430dera, lilfrosted) did a real rewrite but only on one day.

Note: "opened the app again" is a weak signal here on purpose — the app relaunches at login,
so it can look like a return when nobody touched it. The 24% number is the one to trust.

### 4. What are they using to rewrite?

**By type of action** (this property only exists in 0.1.9+, so 20 of the 40 real rewrites are
from older builds and have no type recorded):

| Action | Real uses | Tutorial uses |
|---|---|---|
| Saved button | 16 | 13 |
| Reply | 3 | 3 |
| Regenerate | 1 | 0 |
| Custom instruction (typed free text) | **0** | 1 |
| No type recorded (old build) | 20 | 30 |

**Which saved button:**

| Button | Real uses | Tutorial uses |
|---|---|---|
| Natural Japanese | 7 | 4 |
| Unnamed / older build | 9 | 1 |
| Polite | **0** | 8 |
| Translate to English | **0** | 5 |
| Email | **0** | 4 |

This is the sharpest finding in the whole dataset. Three of the four stock buttons —
Polite, Translate to English, Email — have been pressed **only inside the tutorial and never
once in real work**. "Natural Japanese" is the only button carrying the product. The free-text
custom instruction has never been used for real either.

**Which app they are writing in** (real rewrites):

| App | Rewrites |
|---|---|
| LINE | 11 |
| Microsoft Teams | 8 |
| Chatwork | 4 |
| Slack | 4 |
| Dia browser | 2 |
| Chrome / Edge / Notepad / Spotify / Finder | 1 each |
| Unknown (capture failed) | 5 |

Chat is basically the whole product: LINE + Teams + Chatwork + Slack = 27 of 40.

### 5. What is breaking

**32 failures from outside users, and every one that recorded a reason was a text-capture
failure** — the app could not read what the user was writing. Not one was a model error or a
network error.

Of the 12 failures that carry the newer detail:

| Where | Failures |
|---|---|
| Nothing focused / unknown | 7 |
| Finder | 3 |
| Our own app | 1 |
| Chatwork | 1 |

Since 2026-08-24 (when the "started" event shipped, giving a proper denominator), outside
users pressed a button **58 times**, and **29** of those ended with the text going into the
app — about half. 17 attempts failed outright.

The Accessibility permission is not the main blocker: 12 people granted it out of 10 who
were prompted (some grants pre-date the prompt event). People are getting through the
permission and then hitting capture failures anyway.

### 6. Money

`desktop_checkout_completed` has never fired. **Zero paying customers.** 13 people have seen
the welcome offer.

---

## 【TODO / 次のアクション】

1. **Fix text capture first.** It is the only failure type in the wild, it kills a third of
   attempts, and 7 of 12 detailed failures had nothing focused at all — meaning users are
   pressing the pill before clicking into a text box. Consider disabling or warning on the
   pill when there is no focused text field, rather than failing after the press.
2. **Ask why the generated text is thrown away.** 35% insert rate on real rewrites vs 84% in
   the tutorial is the core product signal. Worth watching a few of the 5 repeat users
   closely, or asking them directly — there is no session replay on macOS, so the events
   will not answer this on their own.
3. **Rethink the default button pack.** Polite, Translate to English and Email have zero real
   uses. Shipping four buttons where only one gets used means three-quarters of the row is
   dead space on first run.
4. **Target chat apps explicitly.** LINE, Teams, Chatwork and Slack are 27 of 40 real
   rewrites. The onboarding tutorial should probably practise in a chat context, not a
   generic one.
5. **Double down on TikTok.** It is 7 of 12 known sources. Instagram and X have produced 3
   between them.
6. **Check `desktop_rewrite_abandoned`.** This event does not exist in the project taxonomy —
   it has never fired once. Either it never shipped or it is unreachable, which means the
   "one started ends in exactly one terminal event" invariant is not observable in production.

---

## Caveats — read before quoting any number above

- **The owner dominates the raw data.** The owner account alone has 83 real rewrites across
  4 days; all 21 outside users together have 40. Any unfiltered chart is the founder's habits.
- **Three of the 21 have no email** — they installed, opened once, never signed in, and left.
  They are counted as outside users, which slightly depresses the percentages.
- **`rewrite_type` and `button_key` only exist in 0.1.9+**, so 20 of 40 real rewrites have no
  type recorded. The button table above is directionally right, not complete.
- **"Real" slightly understates.** 7 rewrites were `scope: scratch` written inside our own
  overlay — genuinely real, but they report our bundle id and so land in the tutorial column.
- **These are tiny numbers.** 21 people and 40 rewrites. Treat every percentage as a
  direction, not a measurement.

---

# Follow-up: three hypotheses tested (2026-08-28)

## 1. "Did they see the skip button, or did they think they had to pay?" — **No. Falsified.**

Two independent pieces of evidence, both decisive.

**Nobody hesitated on the offer page.** Every single person who reached it moved past it in
seconds:

| User | Offer shown | Onboarding completed | Time on page |
|---|---|---|---|
| sahildhapola7505 | 22:16:33 | 22:16:38 | **5s** |
| lilfrosted | 15:37:12 | 15:37:20 | 8s |
| y.sota15104290 | 16:45:23 | 16:45:33 | 10s |
| natsuki.kataoka | 15:18:01 | 15:18:12 | 11s |
| takuto430dera | 00:29:43 | 00:29:54 | 11s |
| kentaromoriya19 | 13:54:38 | 13:54:50 | 12s |
| dai600417 | 19:54:21 | 19:54:35 | 14s |
| hirochan3tani | 21:50:50 | 21:51:07 | 17s |
| what3.14nnn | 20:09:06 | 20:09:24 | 18s |
| matsumoto95 | 13:07:02 | 13:07:23 | 21s |
| shionpark06 | 23:58:30 | 23:58:53 | 23s |
| taiyounikonikotaiyou | 11:22:29 | 11:22:52 | 23s |
| kaito.orito | 23:22:15 | 23:22:41 | 26s |

**13 of 13 reached the offer and 13 of 13 completed onboarding.** Median time on the page is
14 seconds. Nobody stalled, nobody abandoned there, nobody was confused about how to move on.

**`desktop.checkout_intents` has 0 rows.** Not one person has ever pressed
「この価格で始める」 in the entire history of the app. If people believed payment was
required, at least some would have clicked the buy button. Zero did.

The skip link reads 「あとで」 and the page carries the sentence
「あとで決めても大丈夫です。この価格はホーム画面からも受け取れます。」 It is working.

**Where they actually leave: right after onboarding ends, in under a minute.**

| User | Onboarding done | Last activity ever | Gap |
|---|---|---|---|
| matsumoto95 | 13:07:23 | 13:07:49 | **26s** |
| what3.14nnn | 20:09:24 | 20:10:00 | 36s |
| taiyounikonikotaiyou | 11:22:52 | 11:23:31 | 39s |
| y.sota15104290 | 16:45:33 | 16:46:33 | 60s |

All four did their tutorial rewrites, finished, closed the window, and never came back.
**None of them recorded a single failure.** Nothing broke. They simply stopped.

## 2. "Capture works — maybe they just didn't know how to use it?" — **Half right.**

**Right: the backend and the model are not the problem.** In `desktop.rewrite_events`,
`status <> 'ok'` is **0 for every external user**. Every rewrite that reached the server
succeeded. The 32 failures in PostHog are all client-side capture failures that never made
it to a request.

**Right: several failures are genuinely people pointing it at nothing.** Of the 12 failures
with the newer detail, 7 had nothing focused at all and 3 were in **Finder** — there is no
text field in Finder to rewrite. That is misuse, not breakage.

**Right: the output quality is good.** Text has been retained since **2026-08-25** only
(49 rows; everything before that is null). What is readable is strong — real business
Japanese being properly softened, and rough English being cleaned up. Two real examples:

- Chatwork, `natural`: 「基本的には承諾済みでありますが…グッズ制作の概要をペライチで良いのでいただけますか？」
  → 「基本的には承諾済みですが…グッズ制作の概要をペライチで構いませんのでいただけますでしょうか？」
- Teams, English: "no data is display showing , is there no data or its a issue"
  → "No data is being displayed. Is there no data available, or is this an issue?"

**Wrong: there is a real problem, and it is *after* the rewrite is generated.**

| App | Rewrite finished | Inserted | Copied |
|---|---|---|---|
| Chatwork | 4 | **0** | 0 |
| Slack | 4 | **0** | 0 |
| LINE | 11 | 3 | 0 |
| Teams | 8 | 6 | 0 |
| Dia / Chrome | 3 | 2 | 0 |

Teams works (clipboard path, 6 of 8). **Chatwork and Slack are 0 for 8.** LINE is 3 of 11.

kentaromoriya19 is the clearest case: **7 good business-Japanese rewrites in Chatwork and
LINE, and he inserted none of them.** In Supabase all 7 rows have `accepted = null`. He is
still active as of 8/28.

## 3. Why we cannot yet say whether that is a bug or a choice

`OverlayController.writeBack`'s failure path (`App/Overlay/OverlayController.swift:1478`)
**emits no analytics event at all.** On a failed insert it shows the user
「挿入できませんでした。文章をクリップボードにコピーしました。」, puts the text on the
clipboard, and re-presents the panel — and PostHog is told nothing.

So "finished but never inserted" is currently indistinguishable between:

- the user looked at the result and dismissed it, and
- the user pressed 挿入, the write threw, and they gave up.

One clue points at the second: `desktop_rewrite_copied` is **0 across every app**. If
inserts were succeeding and users were declining, some would have used the copy button.
Nobody has used it even once.

The owner's own data is consistent with "it worked when we tested it" but is far too small
to prove the app works for everyone: Slack 2→1 inserted, LINE 1→1, Chrome 1→1.

## Revised priorities

1. **Instrument the insert-failure catch block.** One event with the app, the write strategy
   and the error. This is the single highest-value fix in the codebase right now — it turns
   the biggest open question into a number within days.
2. **Investigate the insert path in Chatwork and Slack specifically.** 0 for 8 with good
   rewrites sitting behind it is the most likely real bug.
3. **The offer page is fine. Leave it alone.** The drop-off is the 30 seconds *after*
   onboarding, not the paywall.
4. **The gap is "first real use".** People finish the tutorial and never try it on their own
   text. Consider ending onboarding by pointing them at a real app rather than at a
   completion screen.
