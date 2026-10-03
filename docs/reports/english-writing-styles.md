# English writing styles

English now has explicit guidance for all 36 universal styles, rather than relying on translated Japanese politeness labels. The target is usable everyday English: correct and idiomatic, faithful to the author's intent, and formatted for the surface. Normal does not mean shorter or more formal. This is the intended behavior; generated-output quality remains unverified.

## Writing basis

Applied [Writing Clearly and Concisely](https://github.com/obra/the-elements-of-style/blob/main/skills/writing-clearly-and-concisely/SKILL.md) as an editing reference: concrete wording, logical grouping, and removing needless words. Its historical essay conventions are not blanket rules for chat. In particular, clarity does not justify deleting details, changing a negative into an affirmative, inventing an actor to force active voice, or expanding every conversational fragment.

[Purdue OWL's email guidance](https://owl.purdue.edu/owl/general_writing/academic_writing/email_etiquette.html) informs greetings, readable paragraphs and signatures; [its business-tone guidance](https://owl.purdue.edu/owl/subject_specific_writing/professional_technical_writing/tone_in_business_writing.html) informs audience-appropriate courtesy. Our product edits a captured body, so it must not insert a subject header or invent contact details. [Microsoft's contractions guidance](https://learn.microsoft.com/en-us/style-guide/word-choice/use-contractions) supports natural conversational wording. These are editorial references, not runtime dependencies or universal rules for every English-speaking culture.

Product decisions: everyday professional writing can use contractions; considerate wording need not add apologies or gratitude; a firm refusal stays firm. Preserve valid regional spelling and intentional dialect. Specific user preferences override defaults. The skill was read from its source, not installed globally.

## Questions and choices

Bold choices are the middle defaults. Semantic IDs and saved profiles are unchanged.

| Context | Question | Choices |
| --- | --- | --- |
| Email | What tone should your emails have? | Relaxed / **Professional** / Formal |
| Email | How should we organize your emails? | Keep my structure / **Improve readability** / Main point first |
| Work messages | What tone should work messages have? | Casual / **Natural** / Professional |
| Work messages | How much detail should messages have? | Concise / **Standard** / Detailed |
| Personal messages | What tone should your messages have? | Casual / **Natural** / Composed |
| Personal messages | How should we use line breaks? | Keep line breaks / **Natural breaks** / More breaks |
| Other | What tone should your writing have? | Conversational / **Natural** / Formal |
| Other | How much editing would you like? | Light touch / **Improve flow** / Restructure |

Email organization changes the body, not the greeting/signature requirement. Personal line breaks separate topics without mechanically splitting every sentence. Other editing strength changes how much structure may move, not the minimum correctness standard. Tone previews illustrate the same facts and intent; differences can be small when the message already fits more than one tone.

## Prompt implementation

- `supabase/functions/desktop-rewrite/english_style.ts`: common English editing rules, 12 context-specific voice modules, and three whole-email frame examples. Included by `style_prompt.ts` for styled requests only. Instructions condition their application on English output; no heuristic language detector and no forced translation based on UI locale.
- Shared detail modules still supply all three settings for each context, including legacy work IDs. Current instructions and saved preferences retain precedence. Selections receive tone without an email template or whole-body structure. Reply audience and stance rules remain in force.
- English quality covers articles, tense, agreement, prepositions, shorthand and run-ons; preserves quotations, code, names, dates, uncertainty and responsibility. It rejects stock filler, weakened deadlines, invented excuses and padding. Ordinary contractions are allowed in professional email and chat. Formal does not mean ornate.
- Full English email examples use Hi/Best for relaxed, Hi/Best regards for professional, and Dear/Kind regards for formal, preserving appropriate existing conventions. Known names follow the trusted identity rules; unknown names use placeholders. Explicit body-only instructions still win.
- `App/Main/WritingStyleView.swift`: English questions, options, notes examples and previews. Email banner identifies the previews as body excerpts. Japanese/Chinese strings and persisted choices retain their existing meanings.

## Authored acceptance examples

These are editorial targets, **not model outputs or test results**. Equivalent faithful wording is acceptable.

Default email input: `got it, let me know once you pass the first interview`

```text
Hi [Recipient name],

Got it. Please let me know once you pass the first interview.

Best regards,
[Your name]
```

The saved sender name replaces its placeholder when available. Do not add congratulations: passing the interview is still a condition, not an established fact.

Default work input: `ive shared the revision schedule works for me but cost isnt confirmed pls review by Friday 5pm if you cant let me know today`

```text
I've shared the revision. The schedule works for me, but the cost isn't confirmed yet. Please review it by Friday at 5 pm. If you can't, let me know today.
```

The deadline cannot become “when you have a chance”; the author has not promised to confirm the cost. A personal message such as “I'll be there at 3 tomorrow. Let's meet at the station.” is already sendable and needs no added courtesy, enthusiasm or signature.

## Verification and delivery

- 65 backend tests pass. The English matrix covers all 36 styles across polish, compose, reply and selection, with selected voice/detail routing and scope boundaries. Additional cases cover source/configured-language mismatches, translation directions, mixed text and isolated preferences.
- Type check passes for the production package; changed prompt/test files pass lint.
- 432 legacy request combinations preserve exact parsing and system/user prompts against v27.
- 104 synthetic evaluation payloads validate locally: the previous 54 plus all 36 English combinations and 14 English edge cases. The evaluator now preserves each case's configured writing language instead of overwriting it with Japanese. Tests of strings and payloads do not establish generated quality.
- Native Debug build succeeds with signing disabled. All 324 native layout combinations pass; the four English settings pages were visually inspected at the narrow width. The standalone harness does not load bundled app logos. The installed app was not replaced.
- `desktop-rewrite` v28 is active with JWT verification enabled. Deployment uses downloaded v27 files and changes only `style_prompt.ts`, adding `english_style.ts`. Existing production endpoint, billing, auth, logging, retention and reply validation are preserved. No iOS, database or phone-prompt changes.

Live output evaluation is pending: the immediately preceding email evaluation returned HTTP 429 (`quota_month`, 30/30). This revision has not retried metered generations or altered quota. Use an authorized test account with available quota for semantic review. Check meaning, voice, formatting and absence of invented content, not just factual substring anchors.

```sh
python3 scripts/evaluate-writing-styles.py --output /private/tmp/english-style-cases.json
python3 scripts/evaluate-writing-styles.py --live --case en-work_chat-neutral-balanced --output /private/tmp/english-style-results.json
```

Live mode requires the endpoint, user JWT and publishable key environment variables documented in the script. The backend prompts apply immediately; the changed English settings copy requires a rebuilt desktop app.
