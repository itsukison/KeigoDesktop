# Complete email formatting

Universal whole-email requests now produce a salutation, spaced body paragraphs, conventional closing and sender signature for all nine voice/organization combinations. This applies to polishing a draft, composing a new message and replying. The organization choice still controls the body order; it does not disable the email frame.

Recipient names must come from a clearly identified addressee in the supplied draft, instruction or reply evidence. A third-party mention or quoted author is not recipient evidence. If the addressee is unknown, use `[宛名]様` for Japanese or `[Recipient name]` in an English salutation. Preserve an existing sender signature; otherwise use the authenticated profile's display name, or `[あなたの名前]` / `[Your name]` when unavailable. Ordinary whole-email polish now requests this trusted profile identity, as composition and replies already did. Client-supplied author names remain ignored.

Default English closing: “Best regards,” followed by the sender name on the next line. Japanese uses a natural short closing such as “よろしくお願いいたします。” No automatic subject header, corporate introduction, invented relationship or new factual content is added. Existing greetings and automatic signatures visible in the captured draft are retained without duplication. Missing-name slots are the user-authorized exception to the placeholder ban; missing dates, reasons, promises and other facts cannot acquire new placeholders.

Explicit body-only or non-email-artifact instructions and saved signature preferences override the default frame. Selected fragments never receive the frame. Inherited reply rules were adjusted only for styled whole-email replies to remove the conflicting name-free/placeholder-ban policy; participant, audience and stance protections remain intact. Legacy and non-email prompts are unchanged.

## Verification

- 63 backend tests pass. New coverage exercises all nine email styles in whole-draft, compose, empty-reply and drafted-reply operations; conflicting bans are absent. Fragment scope, non-email isolation, signature/instruction data, trusted identity, and identity lookup policy are covered.
- Endpoint type check and changed prompt/test lint pass.
- 432 legacy combinations have byte-identical parsed results and compiled system/user prompts compared with production v26.
- 216 non-email style/operation combinations retain byte-identical compiled system/user prompts compared with v26.
- All 54 synthetic evaluation payloads validate. Six added cases cover English/Japanese missing recipients, an existing signature, a third-party name, explicit body-only instructions and a saved automatic-signature preference. These fixtures and prompt tests are not model-quality results.
- `desktop-rewrite` **v27** is active with JWT verification enabled. All downloaded runtime files exactly match the submitted package.

The package uses the downloaded v26 production baseline. Only `style_prompt.ts`, `style_modules.ts`, `prompt.ts`, and the import/identity predicate in `index.ts` changed. Existing production quota, authentication, retention/logging and reply validation remain intact. Unrelated local endpoint differences were not deployed. No client rebuild or database/iOS change is needed for this server-side fix.

Live testing was attempted with one synthetic English email after deployment. The account is still at its monthly limit (HTTP 429, `quota_month`, free plan, 30/30). No output was returned, so generated-output quality remains unverified. No quota was altered and no automatic paid retry was made.

Reproduce when an authorized test account has quota, using the environment variables documented by the evaluation script:

```sh
python3 scripts/evaluate-writing-styles.py --live --case email-en-missing-recipient --output /private/tmp/email-format-live.json
```

Review the generated email for a recipient placeholder, a natural faithful body, a conventional closing, and the correct sender name or fallback. Also run the Japanese, existing-frame, third-party, body-only and saved-no-signature cases before claiming full semantic acceptance.
