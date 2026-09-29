# PUBLISHING.md — scheduling the slideshow posts

**Read `GTM.md` for strategy and `FORMAT-TESTS.md` for what is being tested.** This file
is the operational record: which accounts exist, what each platform will accept, and the
traps that have already cost a failed API call or a wasted upload window.

Scheduling runs through **two schedulers, on deliberately separate accounts** — Zernio for
the Japanese personas, Buffer for the English ones. **As of 2026-08-22 no account is
connected to both tools**: Buffer's third channel slot went to Instagram
`hannah_keigobutton`, which displaced IG `yuna_keigobutton` there. Zernio owns every
Japanese account, Buffer owns every English one, and the double-post hazard the earlier
version of this file warned about no longer exists. **If yuna is ever reconnected in
Buffer the warning comes back with it** — it is the only handle both tools have held.

- Zernio MCP: `accounts_list`, `media_generate_upload_link`, `media_check_upload_status`,
  `posts_create`, `posts_list`.
- Buffer MCP: `get_account`, `list_channels`, `get_channel`, `create_post`, `list_posts`.
  `create_post` takes `assets[].image.url` directly — any public URL, no upload token step.

---

## 1. Accounts — the personas do not line up across platforms

| Platform | Handle | Account ID |
|---|---|---|
| TikTok | `ruka_keigobutton` | `6a6b64c0df17280d93f47e27` |
| TikTok | `saya_keigobutton` | `6a72f1b4d0fe733d1a456ce0` |
| TikTok | `yuri_keigobutton` | `6a7409d6d0fe733d1a8d67df` |
| Instagram | `yuna_keigobutton` | `6a6b7765df17280d93f65ff5` |

### 1.1 Buffer — the English accounts

Organization **"My Organization"** (`6a5ca2caaf5abceaf84fa281`), owner `keigobutton@gmail.com`,
timezone `Asia/Tokyo`.

| Platform | Handle | Channel ID | Use |
|---|---|---|---|
| TikTok | `keigobutton` | `6a5ca30ae2638b94d795ed09` | **the English track — TikTok** |
| Instagram | `hannah_keigobutton` | `6a896093ccaf649a67f47b03` | **the English track — Instagram** (added 2026-08-22) |
| YouTube | `alittlelife` | `6a5ca31fe2638b94d795ed54` | unused by this format |

`hannah_keigobutton` is an Instagram **Professional** account with
`metadata.defaultToReminders: false`, so Buffer auto-publishes it — no phone reminder step.
It needs `metadata.instagram: {type: "post", shouldShareToFeed: true}` on `create_post`.

**IG `yuna_keigobutton` (`6a5ca371e2638b94d795ee90`) is no longer a Buffer channel.** The
free plan caps channels at 3 and hannah took the slot. yuna is now Zernio-only.

**None of `ruka`/`saya`/`yuri`/`yuna` exist in Buffer**, and neither `keigobutton` nor
`hannah` exists in Zernio. The two tools address different accounts by design.

Free-plan limits that constrain the work: **3 channels (all three used)**, **10 scheduled
posts PER CHANNEL**, and **Insights only cover the last 31 days** — a longer window returns
a hard error, so any baseline worth keeping has to be copied into `FORMAT-TESTS.md` before
it ages out.

**The scheduled-post cap is per channel, not per organization.** `get_account` reports
`limits.scheduledPosts: 10` at the organization level and the error text says *"You have 10
scheduled posts out of 10 allowed"*, both of which read as org-wide — they are not. On
2026-08-22 the org held 20 scheduled posts across two channels (10 each) and the 21st was
refused because **hannah** was full, while `keigobutton` accepted its 10th in the same
minute. Plan for 10 per channel, and do not read the error as an org total.

**Drafts are exempt from that cap** (`create_post` with `saveToDraft: true` succeeded on a
channel already at 10/10). A draft carries text, assets and alt text but no `dueAt`, so it is
the right parking spot for a rendered post that has nowhere to land yet — promote it with
`edit_post` once a slot frees. It is also invisible to a queue audit that filters on
`status: scheduled`, so **list drafts too**.

**`deletePost` is not in `allowedActions` for any sent post.** Published history cannot be
removed through Buffer at all; that is a TikTok-app operation.

**There is no `ruka_keigobutton` on Instagram.** Instagram runs two different personas —
`yuna` (Japanese, Zernio) and `hannah` (English, Buffer) — and neither shares a name with a
TikTok handle. Do not assume a handle exists on both platforms.

**The handle is burned into every card slide**, so the posting account is a *render*
dimension, not just a scheduling detail — `render.py` keys it as `account`, and
`ja-00N` (ruka) and `ig-00N` (yuna) are separate renders of the same post, as are
`en-00N` (keigobutton) and `en-ig-00N` (hannah). Posting one account's files under another
shows the wrong handle and reads as a reposted account.

`posts_create` needs an explicit `account_id` whenever more than one account exists on
the platform. Never let it pick.

---

## 2. Platform limits that will fail the call

- **TikTok photo posts cap the title at 90 characters.** The content field *is* the
  slideshow title. A 294-character caption is rejected outright with
  `TIKTOK_PHOTO_TITLE_TOO_LONG`. Write a short TikTok title and keep the long caption
  for Instagram — they are genuinely different fields, not the same text truncated.
- **Instagram carries the full caption** (numbered app list, save prompt, comment
  prompt, CTA, hashtags). It has one text field, so nothing here applies to it.

### 2.1 TikTok photo posts have *two* text fields, and the MCP wrapper can only fill one

This is the cause of "the title and the body text repeat the same thing", and it is not a
platform limit:

| Field | Becomes | Limit | Notes |
|---|---|---|---|
| `content` (top level) | the photo **title** | **90 chars** | **hashtags and URLs are auto-stripped** |
| `tiktokSettings.description` | the **caption** under the carousel | 4,000 chars | where the real caption belongs |

**The MCP `posts_create` wrapper has no `tiktok_settings` parameter, so `description` can
never be set through it.** Zernio's publisher then fills the block in itself with
`description: ''` — visible in post 003's stored record — and TikTok renders the title text
as the post's only text. Title and body are the same string because there is only one
string.

Two consequences that have been shipping on every JP TikTok post:

- **The hashtags never reach TikTok at all.** They are inside `content`, which is the
  title, which strips them. `caption.txt` carries a full 8-hashtag caption that was never
  sent.
- **Neither does the comment prompt or the numbered app list.** An earlier version of this
  file recorded "TikTok loses the comment prompt" as a platform property and told the
  reader not to treat the Instagram/TikTok comment gap as a format signal. **That was
  wrong.** The gap is this bug, and TikTok comment counts for posts 001–003 measure a post
  with no caption.

The fix is §4.1's full tool: `posts_create_post` / `posts_update_post` accept
`tiktok_settings`. Send the short title as `content` (no hashtags — they are discarded) and
the `caption.txt` body as `tiktok_settings.description`.

### 2.2 Music on a TikTok photo carousel — one flag, not a track picker

Zernio can put sound on a TikTok photo post, but **it cannot choose the song.**
`tiktok_settings.auto_add_music: true` tells TikTok to attach a track itself, and there is no
field anywhere in the API for naming one. Send it alongside `media_type: "photo"` and
`photo_cover_index: 0`; all three persist into `platformSpecificData.tiktokSettings` and read
back on `posts_get`.

Two things this is not:

- **It is not the Instagram audio catalog.** Zernio does expose that
  (`instagram_search_instagram_audio` / `instagram_get_instagram_audio`, trending list when
  `q` is omitted), and it returns real `audioId`s — but those are only usable as
  `platformSpecificData.audioConfiguration.audioId` **on a Reel**, and only for an Instagram
  account connected through **Facebook Login**. Our carousels are photo posts, not Reels, so
  the catalog cannot reach them. It is also moot for `hannah`, which lives in Buffer.
- **It is not retroactive.** JP posts 001-006 shipped with no music flag at all, so they are
  silent where 007-012 will not be. That is a second variable inside the series; see
  `FORMAT-TESTS.md`.

## 3. Media upload

`posts_create` takes `media_urls` — any publicly reachable URL. Two routes:

**Browser upload (fallback).** `media_generate_upload_link` → the user drags files →
`media_check_upload_status` returns URLs with the original filenames preserved.

- **The token expires in about 30 minutes.** Mint it immediately before the user is
  ready, not while still discussing captions. Three tokens were burned learning this.
- **Rename before uploading.** Every post directory contains `01_hook.png`, so a flat
  upload collides. Stage copies into `pipeline/out/_upload/` named
  `<account>-<post>-<slide>.png` — filenames survive the round trip, which is the only
  thing making 30 files mappable back to the right post *in slide order*.
- **Verify slide order before creating the post.** The hook must be the first URL in
  `media_urls`; the carousel order is the URL order.

**Public host (current).** A browser drag puts a human in the loop on every post. At
4 accounts × 5–7 posts/day that is 20–28 uploads a day and it is the bottleneck that
kills `GTM.md` §3's volume thesis. Two options:

- **Supabase (current default)**: the `marketing-media` bucket is **public**. The
  Supabase MCP can inspect the project and policies but does not expose binary Storage
  uploads. Supabase CLI 2.109 does: link the production project, then use
  `supabase storage cp -r <staging-dir> ss:///marketing-media/<versioned-path> --linked
  --experimental`. It authenticates through the logged-in Supabase profile, so no
  `service_role` key enters the shell or repository. Public media URLs are stable at
  `https://<project-ref>.supabase.co/storage/v1/object/public/marketing-media/<path>`.
  Stage collision-safe filenames first and verify every URL returns HTTP 200 before
  calling `posts_create`.
- **GitHub Pages**: already in use for the Sparkle appcast. Slide PNGs are public
  anyway, so this needs **no secret at all** and nothing adjacent to the user database.
  Still a valid fallback for an unattended job.

---

## 4. Timing

**Every scheduled time in both tools is an absolute UTC instant. Nothing is stored,
echoed, or displayed in JST, and neither dashboard converts for you.** Reading a Zernio
calendar and finding `13:00` on a post meant for 22:00 JST is the tool being correct and
the record being unreadable — but the same illegibility is what let three posts go out at
the wrong hour on 2026-08-20/21 without anyone noticing. §4.1 is not advice.

### 4.1 The scheduling contract — absolute times only, never an offset

**The Zernio MCP's named tools are a lossy subset of its API. Do not use them to write.**
`posts_create` takes `content`, `title`, `media_urls`, `platform`, `account_id`,
`is_draft`, `publish_now` and `schedule_minutes` — and nothing else. Missing from it:
`scheduled_for`, `timezone`, and `tiktok_settings`. Its only scheduling input is
`schedule_minutes`, *minutes from now*, counted against a server clock the caller never
observes, so a wall-clock target has to be converted into a relative offset that cannot be
checked at the call site. Both of the 2026-08 defects — the wrong hours (§5) and the
duplicated TikTok title (§2.1) — are the same defect: a field the API has and the wrapper
does not.

**The full tools are reachable through `call_tool`.** `search_tools` lists them;
`posts_create_post` and `posts_update_post` accept the real request body:

| Field | Why it matters |
|---|---|
| `scheduled_for` | absolute ISO instant — the fix for §5 |
| `timezone` | defaults to `"UTC"`. Send UTC in `scheduled_for` and ignore this |
| `tiktok_settings` | the TikTok caption (`description`) — the fix for §2.1 |
| `title` | separate title field. **Not** the TikTok photo title, which comes from `content` |
| `platforms` | `[{platform, accountId}]`. **Required whenever `tiktok_settings` is sent** — a 400 otherwise |
| `media_items` | `[{type: "image", url}]`, in slide order |

So one call, not three:

```
call_tool posts_create_post {
  content: "<short title, no hashtags, ≤90 chars>",
  media_items: [{type: "image", url: "…01_hook.png"}, …],
  platforms: [{platform: "tiktok", accountId: "<id>"}],
  tiktok_settings: {description: "<the caption.txt body>"},
  scheduled_for: "2026-08-22T13:00:00Z"
}
```

Then `posts_get` and assert the time ends **exactly** `:00:00+00:00`. A fractional second
or an off-minute value proves a relative offset was used after all: `schedule_minutes`
inherits the millisecond of the request, so `13:02:03.332000+00:00` is a signature, not a
rounding artifact.

If the wrappers are used anyway, `posts_create` is a **placeholder, not a schedule** —
follow it with `posts_update --scheduled_for <UTC ISO with `Z`>` and verify. `posts_update`
cannot repair a caption; only `posts_update_post` can.

Buffer has no equivalent hole — `create_post` / `edit_post` take `dueAt` as ISO 8601 with
an explicit offset. Write it in the **audience's** offset (`-04:00` for US Eastern) so the
record states its own intent; Buffer normalises to `Z` on read-back.

**But `edit_post` re-validates the whole post rather than merging it.** A reschedule must
resend `text`, `assets` (map `source`→`url`, `thumbnail`→`thumbnailUrl`, carry every
`altText`) and `metadata`. Sending only `postId` / `mode` / `dueAt` fails with
`Post must have either text or media., TikTok posts require at least one image or video.`
The post is left untouched, so the failure is safe — but it means every reschedule needs a
`get_post` first, and `list_posts` already returns the asset URLs and alt text needed.

### 4.2 The conversion table — read it, do not do the arithmetic

**JST is UTC+9 and has no DST**, so the Japanese column is fixed permanently:

| JST slot (Zernio — TikTok `ruka`, IG `yuna`) | UTC instant | Use |
|---|---|---|
| **22:00** | `13:00Z` same day | Strongest. Night scroll, phone in hand — which suits a CTA whose destination is a phone app install |
| 19:00 | `10:00Z` same day | Second. Evening, commute home |
| 12:00 | `03:00Z` same day | Lunch |
| 08:00 | `23:00Z` **previous day** | Weakest of the four. The date rolls **back** — the one row that catches people |

**The US column does not hold, because the US observes DST.** The Buffer channel targets
a US audience (`GTM.md` §2.2), so its slot is defined in US local time and the UTC instant
has to move twice a year:

| US slot (Buffer — TikTok `keigobutton`, IG `hannah_keigobutton`) | UTC until 2026-11-01 | UTC from 2026-11-01 |
|---|---|---|
| **12:00 ET / 09:00 PT** | `16:00Z` same day | `17:00Z` same day |
| **17:00 ET / 14:00 PT** | `21:00Z` same day | `22:00Z` same day |
| **22:00 ET / 19:00 PT** | `02:00Z` **next day** | `03:00Z` **next day** |

Why that slot: TikTok's US engagement peak is roughly 19:00–23:00 local, and this single
instant lands inside it in all four continental zones — 22:00 Eastern, 21:00 Central,
20:00 Mountain, 19:00 Pacific. Eastern and Central hold about 76% of the US population and
get the two best hours of it. The previous setting, `01:00Z`, put Pacific at 18:00 — ahead
of the peak — for no gain elsewhere.

Note the date roll: 22:00 ET on Aug 21 is `2026-08-22T02:00:00Z`. A US-evening post always
carries **the next day's** UTC date. Getting this wrong shifts a post by 24 hours, not by
an hour, so it is the more expensive of the two date-roll traps.

**10:00 JST is not a Japanese slot and never was.** It is `01:00Z`, the old US setting, and
`GTM.md` §2.1's windows are actively wrong for the English channel. Do not "fix" a Buffer
post by moving it into a JST slot.

### 4.3 The automated app-intro cadence is three per day

**The app-intro slideshow runs three times per account per day.** Japanese accounts use
08:00, 12:00 and 22:00 JST; English accounts use 12:00, 17:00 and 22:00 ET. These windows
are separated enough to give each post its own distribution cycle. Do not backfill a
missed morning or lunch slot later in the same day; start with the next future slot.

This rule applies only to the automated app-intro format. Manually posted videos keep
their existing cadence and workflow for now. Buffer's 10-scheduled-post cap means the
English queues need rolling refills rather than one large batch.

Higher frequency is an explicit growth choice, but it changes the test environment. Judge
the before/after proof card on per-post conversion and account for same-day competition;
do not present its results as a clean one-variable comparison with the earlier one-post-
per-day controls. `ruka` 001/002 remain especially contaminated because they were only
three hours apart in the same evening window, rather than spread across this cadence.

### 4.4 What the analytics endpoint is worth

**`analytics_get_best_time_to_post` is close to useless right now, and it does not say
so.** Nearly every slot returns `post_count: 1` — one observation, which cannot separate
"this hour is good" from "one post happened to do well." Instagram's top slot showed
2,452 engagement from a single post.

What *is* usable: the returned hours cluster at **3, 10, 13, 23**, which read as UTC are
exactly the four JST rows in §4.2 — lunch, evening, night scroll, commute. That they land
on the canonical Japanese windows is the strongest thing in the data. **The UTC reading is
an inference, not something the API states**, though every other Zernio surface echoes UTC
too. Replace §4.2's JP ranking with real data once slots reach n > 5.

### 4.5 Both dashboards read in the wrong clock, and that is a real cost

Zernio posts carry no timezone at all (§4.1), so its calendar shows UTC. Buffer's channel
`timezone` is `Asia/Tokyo` — correct for the JP accounts, wrong for the account that
exists to reach Americans — so the English queue renders at 11:00 JST when it means
22:00 ET. Neither is a publishing bug; both mean **a human glance cannot audit the queue**,
which is precisely why the 2026-08-20 drift survived a verification pass that this file
records as clean. Until the display is fixed, the audit is `posts_get` / `list_posts` plus
§4.2, never the calendar.

Two open items, neither blocking:

- **Set the Buffer `keigobutton` channel timezone to `America/New_York`** so its queue is
  legible in its audience's clock.
- **Its `postingSchedule` is still JST-tuned** (Thu 21:50, Fri 19:36, …) and is bypassed
  with `mode: customScheduled` for that reason. Retune it to US hours before this channel
  ever uses `addToQueue`.


## 5. Sequence that works

1. `accounts_list` — get IDs, confirm the handle actually exists on that platform.
2. Render every account's set (`render.py ja-001`, `render.py ig-001`, …).
3. Write `caption.txt` beside each set so it is editable and reviewable before posting.
4. Stage uniquely-named copies for upload.
5. Mint the upload token **now**, get the files up, `media_check_upload_status`.
6. Assemble `media_urls` per post in slide order; assert 5 files and hook-first.
7. `posts_create` per account per post with an explicit `account_id`. **This does not
   schedule anything** — whatever `schedule_minutes` lands on is a placeholder (§4.1).
8. `posts_update --scheduled_for <UTC ISO with `Z`>` per post. This is the schedule.
9. `posts_get` every post and assert the time ends `:00:00+00:00`, then
   `posts_list --status scheduled` for the count. Do not trust create confirmations, and
   **do not audit from either dashboard's calendar** (§4.5).
10. Log the variant in `FORMAT-TESTS.md` §3.

### 2026-08-20 — posts 004–006

Uploaded 30 uniquely named PNGs to
`marketing-media/mac-roundups/2026-08-20/` through Supabase CLI and verified every
public URL as `200 image/png`. Scheduled each post to both matching account renders,
one post per account per day at 22:00 JST:

| Post | Date (JST) | TikTok `ruka_keigobutton` | Instagram `yuna_keigobutton` |
|---|---|---|---|
| 004 | 2026-08-22 22:00 | `6a868a713c4e53d2de7365c0` | `6a868a663e3bf80d440d6848` |
| 005 | 2026-08-23 22:00 | `6a868a7ce9cbb6b095ac6aa6` | `6a868a873e3bf80d440d6d34` |
| 006 | 2026-08-24 22:00 | `6a868a91e9cbb6b095ac7451` | `6a868a9b3e3bf80d440d70c8` |

All six records were read back through `posts_get` at exactly `13:00:00+00:00`, and
`posts_list --status scheduled` returned the complete 12-post queue for 001–006.

### 2026-08-20 — English posts 001-006 (Buffer, TikTok `keigobutton`)

The English track's first six posts, scheduled through Buffer to the TikTok `keigobutton`
channel. The 30 PNGs live at the public Supabase prefix
`marketing-media/mac-roundups-en/2026-08-20/`, and all 30 were verified `200 image/png`
before any post was created.

Originally scheduled at `01:00Z` (21:00 EDT / 18:00 PDT). **Times below are the corrected
`02:00Z` slot — 22:00 ET / 19:00 PT — applied 2026-08-21; see the incident entry.** Post 001
had already sent at the old time.

| Post | US local (ET) | Stored `dueAt` | Buffer post ID |
|---|---|---|---|
| 001 | 2026-08-20 21:00 — **sent** | `2026-08-21T01:00:00Z` | `6a869a85e5065537ab4fa30c` |
| 002 | 2026-08-21 22:00 | `2026-08-22T02:00:00Z` | `6a869a95e5065537ab4fa40c` |
| 003 | 2026-08-22 22:00 | `2026-08-23T02:00:00Z` | `6a869a9c5bebcc0cdc2b5626` |
| 004 | 2026-08-23 22:00 | `2026-08-24T02:00:00Z` | `6a869aa334a1034a3c4fd02b` |
| 005 | 2026-08-24 22:00 | `2026-08-25T02:00:00Z` | `6a869aaae5065537ab4fa541` |
| 006 | 2026-08-25 22:00 | `2026-08-26T02:00:00Z` | `6a869ab0c823b06c4842e855` |

All read back through `list_posts --status scheduled` with `hasNextPage: false` — five
records, five assets each, hook first, 1080x1350, no errors.

**Never state a Buffer time in JST.** The whole point of this channel is a US audience, and
the previous version of this table listed these posts as "10:00 JST", which is true, useless,
and the reason nobody noticed 18:00 PDT was ahead of the Pacific peak. §4.2 has the slot.

These were originally spaced one per account per day under the validation rule in effect
at the time; §4.3 now records the three-post cadence adopted on 2026-08-30.

### 2026-08-21 — the schedule was never in Tokyo time, and three JP posts proved it

Reported as "they were not in Tokyo time" after a look at the Zernio calendar. The calendar
reading was a symptom; the cause is §4.1, and posts 001–003 are the damage.

**Root cause: the JP schedule was expressed as an offset from an unobserved clock instead of
an absolute instant** (§4.1). `Marketing/pipeline/out/_schedule.json` records the offsets
that were planned — `{"001": 397, "002": 577, "003": 2017}` minutes — and the stored
`scheduledFor` minus `createdAt` says what was actually applied:

| Post | Account | createdAt | scheduledFor | = JST | Planned | Applied |
|---|---|---|---|---|---|---|
| 001 | TikTok `ruka` | `03:23:22.659Z` | `08-20 10:00:20.378Z` | 19:00 | 397 | **397** ✓ |
| 001 | IG `yuna` | — | `08-20 10:01:25.155Z` | 19:01 | 397 | 397 ✓ |
| 002 | TikTok `ruka` | `03:23:46.764Z` | `08-20 13:00:43.154Z` | 22:00 | 577 | **577** ✓ |
| 002 | IG `yuna` | — | — | — | 577 | `failed`: platform API timeout |
| 003 | TikTok `ruka` | `03:24:06.981Z` | `08-21 07:51:26.926Z` | **16:51** | 2017 | **1707** ✗ |
| 003 | IG `yuna` | — | `08-21 13:02:03.332Z` | 22:02 | 2017 | 1620 (22:00 target) |

**Two distinct faults, and the first correction is to the first version of this entry.**

1. **Posts 001 and 002 hit their planned offsets exactly.** 19:00 **and** 22:00 JST on
   2026-08-20 on the same account is what `_schedule.json` asked for — a §4.3 spacing
   violation that was *planned*, not drift. An earlier draft of this entry claimed both
   published immediately on a `+0` offset; that was wrong, and the arithmetic above is why.
   The consequence is unchanged: `ruka` 001 and 002 are contaminated as a format test,
   because two posts three hours apart competed for one evening.
2. **Post 003 is the only real drift: 1707 applied against 2017 planned, 310 minutes
   early**, landing 16:51 JST — no slot at all. Its record also differs structurally from
   its siblings — it stored `timezone: 'Asia/Tokyo'` where 001/002/004 stored `'UTC'` — so
   its create call was not the same call as the others'. What happened inside that call is
   **not recoverable from the record, and that is the finding**: a relative offset leaves no
   absolute target for anything to be checked against, afterwards or at the time.

Post 003's stored `platformSpecificData.tiktokSettings.description` is `''`, and its
platform sub-document was rewritten at `2026-08-21T07:51:26Z` — the instant it published.
That is Zernio's publisher filling in the settings the caller never sent, and it is the
direct evidence for §2.1's caption bug.

**Posts 004–006 were unaffected and are correct**, because they were scheduled through
`posts_update` with an absolute ISO time. That is now the only sanctioned path (§4.1), and
those six records read back at exactly `13:00:00+00:00` = 22:00 JST.

Fixed on 2026-08-21:

- **Zernio, JP.** 003 IG snapped `13:02:03.332Z` → `13:00:00Z` via `posts_update`. 004–006
  verified on both accounts at exactly `13:00:00Z` (22:00 JST) on 08-22 / 08-23 / 08-24 —
  six records, no change needed.
- **Buffer, EN/US.** All five unsent posts moved `01:00Z` → `02:00Z` (21:00 → 22:00 ET,
  18:00 → 19:00 PT) with `edit_post` at `mode: customScheduled`, and each one re-read with
  `get_post`: five assets, hook first, `metadata` intact. §4.2 has the reasoning.
- §4 rewritten as a contract rather than a table of preferred hours.

**Not fixed, and needing a human:** IG post 002 is `failed` with *"Publishing timed out
during platform API call. The post may have been published externally. Check the platform
before retrying."* **Check `yuna_keigobutton` on Instagram before touching it** — a retry
on a post that did land is a duplicate, and Instagram is the one account both schedulers can
reach. Also unfixed: the two display items in §4.5.

**The TikTok caption (§2.1) is fixed on 004–006.** Each was given its `caption.txt` body as
`tiktok_settings.description` through `call_tool posts_update_post`, sent with `platforms`
(required alongside `tiktok_settings`, else 400) and with `scheduled_for` restated so the
platform sub-document could not be rebuilt without its time. All three read back with the
description present, five media items in slide order, hook first, and `scheduledFor`
unchanged at `13:00:00.000Z`; `posts_list --status scheduled` still returns 7.

The `content` field was deliberately left alone. It is the title, TikTok strips hashtags
from it, and rewriting it would have changed the displayed title for no visible gain.

**Posts 001–003 published without a caption and cannot be repaired.** Their TikTok
engagement is not comparable to Instagram's, nor to 004–006 — the caption is now a second
variable inside this series, on top of the 001/002 spacing overlap. Read
`FORMAT-TESTS.md` §3 with both caveats or the series will be over-read.

### 2026-08-22 — the English Instagram account (hannah), and 5 stray JP posts removed

**The English track now runs two accounts**, TikTok `keigobutton` and Instagram
`hannah_keigobutton`, both in Buffer. Same six roundups, same hook, same captions — Instagram
gets the full `caption.txt` body, which is the field TikTok cannot receive at all (§2.1).

Rendered as a new account dimension: `render.py` gained `BASE_EN_HANNAH` and variants
`en-ig-001`…`en-ig-006`, output at `out/en/must-have-apps/hannah/`. **Shipping the existing
`en-00N` files would have put `@keigobutton` on hannah's cards**, which is the §1 trap, so
all 30 slides were re-rendered and the handle was checked on a card crop before upload.
The 30 PNGs live at `marketing-media/mac-roundups-en-ig/2026-08-22/` and every URL was
verified `200 image/png` before any post was created.

| Post | US local (ET) | Stored `dueAt` | Buffer post ID |
|---|---|---|---|
| 001 | 2026-08-22 22:00 | `2026-08-23T02:00:00Z` | `6a8964be62b911df3f1473af` |
| 002 | 2026-08-23 22:00 | `2026-08-24T02:00:00Z` | `6a8964d0859b98c365e9b6f1` |
| 003 | 2026-08-24 22:00 | `2026-08-25T02:00:00Z` | `6a8964d9859b98c365e9b73b` |
| 004 | 2026-08-25 22:00 | `2026-08-26T02:00:00Z` | `6a8964e1c5db1e9cdcdeb4cf` |
| 005 | 2026-08-26 22:00 | `2026-08-27T02:00:00Z` | `6a8965013869cf6658a04d0d` |
| 006 | 2026-08-27 22:00 | `2026-08-28T02:00:00Z` | `6a8965183869cf6658a05451` |

All six read back through `list_posts` filtered to the hannah channel: six records, five
assets each, hook first, 1080x1350, alt text on every slide, `hasNextPage: false`, no errors.
The series starts at 001 because the account has no history — it is not aligned to the TikTok
numbering, which is already at 003.

**hannah's own `postingSchedule` is JST-tuned** (Mon 18:23, Tue 17:08, …) exactly like the
`keigobutton` channel's, and its `timezone` is `Asia/Tokyo`. Both are bypassed with
`mode: customScheduled`, and both are still on §4.5's open-items list.

**Five Japanese posts were deleted off the English TikTok account.** A batch of six was
created 2026-08-22T02:32Z on channel `keigobutton` — 職場あるある / 恋愛 slideshows, 10 slides
each, queued at 08-22 03:30Z, 08-22 09:30Z, 08-23 00:30Z, 08-23 03:30Z, 08-24 00:30Z and
08-24 03:30Z, i.e. interleaved between the English roundups at 1.5-hour spacing. That is
three posts a day on one account against §4.3, and Japanese creative on the account
`FORMAT-TESTS.md` §1.5 is converting to English, which makes the English five-post gate
unreadable. Confirmed unintentional. Five were removed (`6a890a413869cf66589b4b75`,
`6a890a465b4a6e681b3574ad`, `6a890a4a62b911df3f0faa1f`, `6a890a4fdc319146a2882206`,
`6a890a54c5db1e9cdcd9abd9`); **the sixth, `6a890a3b62b911df3f0fa902`, had already published
at 08-22 03:30Z** and cannot be removed through Buffer at all (see the `deletePost` note in
§1.1) — that is a TikTok-app operation.

**The English account published four times on 2026-08-22, in three different formats.** EN
roundup 002 at 02:00Z, the Japanese slideshow above at 03:30Z, an English Gen-Z video at
08:15Z posted **directly in the TikTok app** (`via: network`, `6a89648a0956530cf04d883d`,
*"But fr like what r u even saying… 💀 #genz #corporatelife"*), and another Japanese
slideshow at 08:42Z. Only the first came from the roundup series. `GTM.md` §4.6 allows one
format per account while a sample is open, so **EN roundup 002's numbers are contaminated**
by three same-day competitors. Note also that posts made in the app never pass through
Buffer, so **auditing the queue does not tell you what the account actually posted** — read
sent history, not just scheduled.

**The lesson is the queue is not single-writer.** Nothing in either tool prevents another
job from adding posts to an account mid-sample, and a calendar glance will not surface it
(§4.5). Audit with `list_posts` before and after scheduling, not just after.

**One Buffer record still needs a human**, not touched here:
`6a781236529955fa90340051`, status `error` since 2026-08-09 — a video rejected for media size
or timeout. Deletable, left alone as a record.

`6a7a0772efdda88d07f26ae4` read as `sending` with *"We weren't able to publish your post to
TikTok"* at 08:41Z and **resolved itself**, sending at 08:51Z. A `sending` record carrying an
error message is not necessarily a failure — Buffer retries, and `deletePost` is absent from
`allowedActions` while it is in flight for exactly that reason. Re-read before acting on one.

### 2026-08-22 — posts 007-012, all four accounts, and music on the JP TikTok set

Six new roundups built on eighteen new utilities, rendered for all four posting accounts
(120 slides) and staged at `marketing-media/mac-roundups-007-012/2026-08-22/`; all 120 public
URLs verified `200 image/png` before any post was created.

**Plates repeat the 001-006 rotation** (`_`, Sky Blue, ios ideas, summer, macbook wallpaper,
`_`) rather than adding a photo. Annotating a new plate is the expensive, error-prone step,
and the hook string has to stay identical across the series anyway (§6), so reuse is the
correct default — a new plate is a new variable, not a refresh.

| Post | Apps (ours always 3rd) | JP 22:00 JST | EN TikTok 22:00 ET | hannah IG 22:00 ET |
|---|---|---|---|---|
| 007 | Dato / Klack / **ours** / ToothFairy | 08-25 `13:00Z` | 08-26 `02:00Z`(27th) | 08-28 `02:00Z`(29th) |
| 008 | Command X / Permute / **ours** / Transloader | 08-26 | 08-27 | 08-29 |
| 009 | Gifski / PDF Squeezer / **ours** / Meta | 08-27 | 08-28 | 08-30 |
| 010 | Time Out / HazeOver / **ours** / Plash | 08-28 | 08-29 | 08-31 |
| 011 | One Thing / System Color Picker / **ours** / Charmstone | 08-29 | 08-30 | **draft** |
| 012 | Folder Peek / Cardhop / **ours** / Shareful | 08-30 | 08-31 | **draft** |

Zernio (JP): 12 posts, TikTok `ruka` + Instagram `yuna`, every one read back at exactly
`13:00:00.000Z` with `timezone: UTC`; `posts_list --status scheduled` returns 18 (004-012 × 2).
Buffer (EN): 6 on TikTok `keigobutton` (08-27 → 09-01 at `02:00Z`) and 4 on IG `hannah`
(08-29 → 09-01), all read back at exactly `02:00:00.000Z`, five assets each, hook first,
1080x1350, alt text on every slide.

**hannah 011 and 012 are drafts, not scheduled** — the channel hit its 10-post cap (§1.1).
Their ids are `6a896d0b37caa42812c903dc` and `6a896d1837caa42812c90429`; give them
`dueAt` `2026-09-02T22:00:00-04:00` and `2026-09-03T22:00:00-04:00` once slots free, and
remember `edit_post` re-validates the whole post (§4.1).

**The JP TikTok set carries `auto_add_music: true`** (§2.2), which 001-006 did not. Both
`ruka` and the caption body went through one `posts_create_post` call each — title in
`content`, caption in `tiktok_settings.description` — so §2.1's caption bug does not touch
this batch.

**Eighteen apps, each used exactly once, none of them a writing tool.** Assets came from the
US Mac App Store and are pinned in `SOURCES.json`. Four candidates were dropped for shipping
only portrait screenshots (Bezel, Session, Soulver, Hyperduck) and replaced by HazeOver, PDF
Squeezer, Folder Peek and One Thing — a portrait screenshot squeezed into the landscape card
slot is the kind of inconsistency that makes our slide read as the ad. **No caption or card
calls any of them free**; most are paid, and only ours carries a price note (§6).

### 2026-08-30 — before/after proof card and three-post cadence

The start-of-work audit found **20 scheduled posts plus two Buffer drafts** across the four
active accounts. Twenty-four new proof posts were then created — six for each account —
using the same roundup controls with only the KeigoButton card replaced by `T1-proof`.

English proof posts were added at 12:00 and 17:00 ET on 2026-08-28 through 2026-08-30;
the existing 22:00 ET controls completed the three-post days. Buffer accepted 10 scheduled
posts per English channel, its hard cap. The new post ids are:

- TikTok `keigobutton`: `6a9185cac95a51407a82f408`, `6a918647ea54576fbefebde0`,
  `6a91864a6b7b5f0a07218fe5`, `6a91864d0a4992cbb290f1da`,
  `6a918650c95a51407a830bad`, `6a9186730a4992cbb2910bb2`.
- Instagram `hannah_keigobutton`: `6a91868c0a4992cbb29111b3`,
  `6a91868fea54576fbefee058`, `6a918691c95a51407a832900`,
  `6a918694c95a51407a8329ac`, `6a9186976b7b5f0a0721aa93`,
  `6a9186996b7b5f0a0721ac23`.

Japanese proof posts are scheduled at 08:00, 12:00 and 22:00 JST on 2026-08-31 and
2026-09-01. Missed 2026-08-30 morning/lunch slots were not backfilled. TikTok has the full
caption in `tiktok_settings.description` and `auto_add_music: true`:

- TikTok `ruka_keigobutton`: `6a93df68d6324e3dfe382534`,
  `6a93df8f172bbb25beddb69a`, `6a93df99f6f668152408a964`,
  `6a93dfba172bbb25beddc4fd`, `6a93dfc4172bbb25beddc70a`,
  `6a93dfb0126a8f436feebbb0`.
- Instagram `yuna_keigobutton`: `6a93dfd6172bbb25beddc89d`,
  `6a93dfedb37c1471ff611579`, `6a93dff7080f808f4fc66170`,
  `6a93e014b37c1471ff611ed6`, `6a93e01daa4fae2b0ea7a38b`,
  `6a93e00bb37c1471ff611c5e`.

Assets are public under `marketing-media/mac-roundups-proof/2026-08-27/` for English and
`marketing-media/mac-roundups-proof-jp/2026-08-28/` for Japanese. Every carousel has five
1080x1350 PNGs in the correct account render. All twelve Japanese posts were read back at
exactly `23:00Z`, `03:00Z` or `13:00Z`, and the final Zernio queue contained 14 scheduled
posts with no new failures. Buffer read-back found five assets and no errors on every new
post. Buffer did not retain alt text on this proof batch despite the supplied image
metadata; the stored image records have empty `altText`.

At 2026-08-30 16:48 JST, after earlier slots had published, the live queue was **22
scheduled**: four on each English account and seven on each Japanese account. The two
`hannah` drafts from posts 011/012 remain drafts and are not included in that total. Two
older Zernio timeout records remain failed and were not retried because Zernio warns that
they may already have published externally.

## 6. Confirm before scheduling

- The bio link is live **and resolves on a phone**. Per `GTM.md` §3.2 it should point at
  the free iOS keyboard, not the Mac DMG — a phone viewer sent to a DMG is a six-step
  funnel across two devices. If the CTA is dead, tap-to-install reads zero and September's
  second threshold fails for the wrong reason.
- Captions do not claim other apps are free unless they are (Dropover is not). Only ours
  carries a price note, and 「無料から」 is accurate against the 50-rewrite tier.
- The hook string is **identical across a series**. Varying it puts two variables in one
  test (`FORMAT-TESTS.md` §5). Series markers (第2弾) are fine.
