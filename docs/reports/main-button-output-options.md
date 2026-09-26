# Main button output choices

The selected targets are J1 A (also allow いただけますと助かります／幸いです), J2 B with 何卒よろしくお願いいたします, J3 B, J4 A, and E1–E4 A. Polite must handle rough notes and shorthand, not only complete sentences. The A/B examples below remain the decision record; they are authored examples, not measured model results. Unknown email names are omitted, preserving the current no-invented-name behavior.

There are only four offered presets per writing language:

- Japanese: 敬語, メール, 英訳, 自然に.
- English: Polite, Email, Shorten, Proofread.
- The Chinese interface currently serves people writing Japanese, so it offers the Japanese four with Chinese guidance. It does not introduce a third writing-language behavior.

## What is actually in the system prompt

Read-only inspection of deployed `desktop-rewrite` version 28 confirms that requests without `writingStyle` use the legacy four-button path. That path preserves meaning, facts, names, dates, numbers and scope; requests only the written result in the structured response; and retains layout unless the button explicitly requests formatting. It does not contain an explicit rule against decorative dash punctuation or a complete email-formatting contract.

The deployed natural-English guidance and complete email frame exist in `english_style.ts` and `style_prompt.ts`, but are conditional on the deferred `writingStyle` payload. The four-button release does not send it. The previous shortening did not move the removed instructions into the shared system prompt.

Implemented locally after reviewing these examples:

- Shared rules: preserve facts, intent, urgency and scope; no invented commitments or names; no model commentary; no canned openings, inflated wording or decorative dash separators. Keep legitimate hyphens in words, names, URLs and identifiers intact.
- Button instructions: two or three concise sentences specifying that button’s tone, transformation and structure. Email must explicitly request its greeting, paragraph breaks and closing. It cannot depend on the deferred universal feature.
- Email identity: use names supplied in the source, omit unknown names, and avoid duplicating greetings or signatures. Never guess one or borrow a third party’s name.

## Japanese

### J1 · 敬語

Input: 資料見た。2ページ目の数字、金曜17時までに直して。

**A · Natural everyday courtesy**

資料を確認しました。2ページ目の数字を金曜17時までに修正していただけますか。

**B · More formal business tone**

資料を確認いたしました。2ページ目の数字につきまして、金曜日の17時までに修正をお願いいたします。

Choice: A is the proposed everyday default. B is more formal without adding apologies or changing the deadline.

### J2 · メール

Input: 佐藤さんへ。資料ありがとう。社内で確認して金曜までに返事する。山田

**A · Approachable email**

```text
佐藤さん

資料を送っていただき、ありがとうございます。
社内で確認して、金曜日までにお返事します。

よろしくお願いします。
山田
```

**B · Standard business email**

```text
佐藤様

資料をお送りいただき、ありがとうございます。
社内で確認のうえ、金曜日までにお返事いたします。

よろしくお願いいたします。
山田
```

Choice: B is the proposed default for メール. Both include real email structure, with no subject header, invented company introduction or added promise.

### J3 · 英訳

Input: 今日はちょっと難しそう。明日の午後ならいけるけど、どう？

**A · Preserve the casual tone**

Today might be tricky. Tomorrow afternoon works for me. How about you?

**B · Smooth, slightly more professional**

Today may be difficult, but I’m available tomorrow afternoon. Would that work for you?

Choice: A preserves the source’s casual register. B changes the register as well as translating. The default should normally follow the source unless you want translation to also polish the tone.

### J4 · 自然に

Input: この機能を使うことで、毎日の文章を書く作業の時間を減らすことができます。

**A · Light, faithful cleanup**

この機能を使うと、毎日の文章を書く時間を減らせます。

**B · More active rewriting**

この機能で、日々の文章作成にかかる時間を短縮できます。

Choice: A stays closer to the user’s voice. B takes more freedom with phrasing. Neither makes everything more formal by default.

## English

### E1 · Polite

Input: Send the revised file by 5 today. I need it for tomorrow’s meeting.

**A · Direct and courteous**

Could you send the revised file by 5 today? I need it for tomorrow’s meeting.

**B · More formal courtesy**

Please send the revised file by 5 today, as I’ll need it for tomorrow’s meeting.

Choice: A is the proposed everyday default. Neither changes “by 5 today” into “when you get a chance” or adds “thanks in advance.”

### E2 · Email

Input: To Sam. thanks for the proposal. ill review it with the team and reply by friday. Alex

**A · Approachable professional email**

```text
Hi Sam,

Thanks for sending the proposal. I’ll review it with the team and get back to you by Friday.

Best,
Alex
```

**B · More formal professional email**

```text
Dear Sam,

Thank you for sending the proposal. I will review it with the team and respond by Friday.

Best regards,
Alex
```

Choice: A is the proposed everyday default. Use paragraph breaks, not fixed-width hard wrapping. No “I hope this email finds you well.”

### E3 · Shorten

Input: I just wanted to check whether you’ve had a chance to review the proposal I sent on Monday. We need your feedback by Thursday so we can finalize the budget on Friday.

**A · Remove padding, preserve every distinct point**

Have you reviewed the proposal I sent Monday? We need your feedback by Thursday to finalize the budget Friday.

**B · Compress into the essential action**

Please send feedback on Monday’s proposal by Thursday so we can finalize the budget Friday.

Choice: A retains the status question and deadline request. B drops the separate status question. A is the safer default for Shorten; B behaves more like a summary.

### E4 · Proofread

Input: Me and Sam was going to send the report yesterday, but we didn’t had the final numbers.

**A · Corrections only**

Sam and I were going to send the report yesterday, but we didn’t have the final numbers.

**B · Corrections plus light polish**

Sam and I planned to send the report yesterday, but we didn’t have the final numbers.

Choice: A preserves the original wording wherever correct. B changes phrasing too. A is the proposed default so Proofread stays distinct from a general rewrite.

## Completed UI changes

Only the essential four are offered in onboarding and in preset replacement. Existing saved configurations and retired pack IDs are preserved. The introduction now lets the user explore the four buttons directly; the customization page contains the name, instruction and editing controls, without Before/After or extra helper copy.

[Introduction preview](four-button-onboarding/choose-buttons.png) · [Customization preview](four-button-onboarding/edit-buttons.png)

Validation: native Debug build passed; 94 focused Swift tests passed, including the one-pack/four-button contract for all interface languages. The introduction and customization screens were rendered at 1080 × 700 points / 2× and visually checked.

The hover row now measures its rendered button content instead of estimating widths with a different font and padding. Four-button, single-button, long-row and side-layout native fixtures were visually checked. [Four-button hover preview](four-button-onboarding/hover-four.png).

The local shared system rules now discourage canned wording and decorative dash separators, preserve legitimate hyphens, and explicitly allow rough-note reconstruction for polite rewrites. Local prompt/request tests passed (30 tests). A patch applied to a temporary copy of deployed v28 preserved the system and user prompts byte-for-byte across 362 universal-style and reply combinations; that comparison ran without TypeScript checking because the downloaded function omitted its shared type declaration. Six ordinary rewrite/selection/compose combinations differed only by the intended shared rule block.

No backend deployment or live generated-output evaluation was performed. The examples below are authored targets, not measured model outputs. Before deploying, apply this narrow shared-rule patch to the current deployed function: the local function predates the deployed universal-style compatibility and must not replace it wholesale. New preset instructions apply when a user chooses the preset set; existing saved account buttons are not overwritten.

## Implemented preset instructions

### 敬語

自然な敬語に整え、ぶっきらぼうな依頼やメモも、そのまま送れる丁寧な文章にしてください。依頼は「〜していただけますか」「〜していただけますと助かります／幸いです」など、文脈に合う表現に。期限や意図を弱めず、堅くしすぎないでください。

Input: 資料見た。2ページ目の数字、金曜17時までに直して。

```text
資料を確認しました。2ページ目の数字を金曜17時までに修正していただけますと助かります。
```

### メール

日本語のビジネスメールに整え、宛名、空行で区切った本文、「何卒よろしくお願いいたします。」の結び、差出人名の順にしてください。宛名と差出人名は原文で分かるものだけ使い、不明なら省略してください。既存の挨拶や署名は重複させず、件名や新しい事情は加えないでください。

Input: 佐藤さんへ。資料ありがとう。社内で確認して金曜までに返事する。山田

```text
佐藤様

資料をお送りいただき、ありがとうございます。
社内で確認のうえ、金曜日までにお返事いたします。

何卒よろしくお願いいたします。
山田
```

### 英訳

仕事のやり取りで使える、自然で少し丁寧な英語に翻訳してください。直訳調や大げさな表現を避け、元の意図や確実さを保ってください。

Input: 今日はちょっと難しそう。明日の午後ならいけるけど、どう？

```text
Today may be difficult, but I’m available tomorrow afternoon. Would that work for you?
```

### 自然に

意味と元の語り口を保ち、不自然な言い回しや重複を直して、読みやすい日本語にしてください。必要以上に言い換えたり、丁寧さを上げたりしないでください。

Input: この機能を使うことで、毎日の文章を書く作業の時間を減らすことができます。

```text
この機能を使うと、毎日の文章を書く時間を減らせます。
```

### Polite

Turn rough notes, shorthand or blunt wording into a complete, natural and courteous message ready to send. Rephrase freely where needed for clarity, while keeping the intended request, facts and deadlines. Use everyday language without adding apologies, excuses or extra deference.

Input: revised file pls today by 5 need for meeting tmr

```text
Could you send the revised file by 5 today? I need it for tomorrow’s meeting.
```

### Email

Turn the text into an approachable professional email with a greeting, readable paragraphs separated by blank lines, and a closing such as “Best,” followed by the sender’s name. Use recipient and sender names only when supplied; omit unknown names. Keep existing greetings and signatures without duplication, and do not add a subject or new facts.

Input: To Sam. thanks for the proposal. ill review it with the team and reply by friday. Alex

```text
Hi Sam,

Thanks for sending the proposal. I’ll review it with the team and get back to you by Friday.

Best,
Alex
```

### Shorten

Remove filler and repetition to make the text shorter. Keep every distinct point, question, request and deadline, and preserve the writer’s tone; do not turn it into a summary.

Input: I just wanted to check whether you’ve had a chance to review the proposal I sent on Monday. We need your feedback by Thursday so we can finalize the budget on Friday.

```text
Have you reviewed the proposal I sent Monday? We need your feedback by Thursday to finalize the budget Friday.
```

### Proofread

Correct spelling, grammar and punctuation. Keep the writer’s wording, tone and structure wherever they are already correct, without polishing or rephrasing for style.

Input: Me and Sam was going to send the report yesterday, but we didn’t had the final numbers.

```text
Sam and I were going to send the report yesterday, but we didn’t have the final numbers.
```

