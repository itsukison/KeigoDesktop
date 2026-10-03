# Universal reply context and draft quality plan

Improve the research reply bar by making its use of the visible conversation and its fulfillment of the user's intent measurable. Start with a general prompt revision on Luna, retain the one-call visual architecture, and use controlled diagnostics to decide whether explicit text evidence or a different model is necessary. This is a solution proposal. No runtime code, model settings, deployment or capture behavior was changed while preparing it.

**What the evidence establishes**

The four fresh exports contain two Gmail captures from one email, one LinkedIn conversation and one Slack thread. They are three conversation families. The [manual review](/Users/itsuki/Desktop/key/laptop/docs/reports/visual-intent-luna-user-trial-review/assessment.json) records their individual findings. The two Gmail captures differ in both intent and scroll position, so they cannot isolate the effect of requesting a longer reply.

| Boundary | Observation | What remains uncertain |
| --- | --- | --- |
| Capture and composer geometry | Both Gmail magenta outlines enclose the intended reply field; frozen intent matches the user's instruction. The long-email JPEG actually sent to the provider was also inspected and its visible body text is human-readable. | Human readability does not establish Luna's reading accuracy after provider image processing. |
| Conversation association | Both Gmail responses claim a region covering the correct email. Their excerpts come from that email. | A region box is a model claim; it does not prove that every line was read or understood. |
| Source selection | The long-email response cites only the closing invitation to apply, despite other program information being visible. | One excerpt may be sufficient for an application acknowledgement. Excerpt count alone does not establish context loss. |
| Composition | The explicit request for a long email produces three short lines without a salutation or developed body. This is a clear failure to fulfill the requested structure and detail. | Whether it comes primarily from prompt ambiguity, conservative generation, visual recovery or model capacity requires a controlled comparison. |
| Visibility | The long-email capture starts midway through the message, and Gmail indicates clipped content. | The model has no source for the missing opening in that capture. Facts from the other capture cannot silently be borrowed. |
| Output completion | The long-email response used 751 total completion tokens against a 2400-token limit. The handler accepts responses only when the finish reason is `stop`. | There is no evidence of token-limit truncation explaining the short draft. Raising the limit is not the first experiment. |

The short Gmail intent, “tell them okay ill apply,” can legitimately yield a short acknowledgement. It is weaker evidence of failure than the explicit long-email request. For a source-recovery test, we must ask for a source-dependent answer; otherwise a generic reply can be correct while demonstrating little context understanding.

**The recurring problem**

Our pipeline successfully correlates a target, returns valid JSON, and can still produce an inadequate draft. The [earlier V4 assessment](/Users/itsuki/Desktop/key/laptop/docs/reports/visual-intent-luna-prompt-v4/assessment.json) records the related pattern: Slack evidence can include a later action report while the draft still presents an older blocker as current. Both cases expose a gap between available source information and the meaning expressed in the final message.

The current `ready` validators check nonempty draft/evidence/regions, geometry bounds, capture IDs and status invariants. They do not assess the source's main purpose, relationships between messages, requested email structure or sufficient detail. These are semantic quality checks. Adding a fixed minimum excerpt count would encourage redundant quotations without establishing comprehension.

The V4 prompt gives explicit coverage guidance to summaries, while replies receive a much smaller instruction about answering supplied answers. “Match the message's genre” leaves email structure underspecified. Numerous preservation rules coexist with little positive guidance for developing a detailed reply using supplied information. That combination is a plausible explanation for generic acknowledgements; it is a hypothesis, not an established cause.

The desired operation is: establish the conversation attached to the composer; understand its purpose and relevant facts; combine those facts with the user's stance and requested operation; produce the requested kind of message. A long source does not automatically require a long reply. A request for a detailed email does require meaningful development, while preserving the user's actual commitments.

**First implementation step and scope**

Prepare one general candidate prompt, provisionally V5, in [contract.ts](/Users/itsuki/Desktop/key/laptop/supabase/functions/desktop-visual-intent/contract.ts). Keep Luna low, the original full-window JPEG at high detail, the existing JSON schema and 2400-token limit fixed for this comparison. Keep the same authenticated research service and tester restriction. The research UI remains preview/export/replay only; the shipping overlay, phone data and local style files remain outside this work.

Reorganize the task guidance around these requirements:

1. Establish composer ownership before selecting relevant content. Read the associated visible message or thread broadly enough to identify its subject, main request and relevant updates. Exclude other panes and every composer from source evidence.
2. Interpret rough intent as an operation plus stance, user facts, language, tone, structure and detail. Explicit requests for a short reply, full email, long email or body-only output must affect the final draft.
3. Select context appropriate to that operation. An acknowledgement needs the subject and authorized stance; a question-answering reply needs the supplied answer and the corresponding question; a summary needs the material situation and timeline. Preserve conditions that affect what the user is agreeing to. Do not turn every reply into a summary of every visible fact.
4. Develop detailed replies through supported context, acknowledgement and organization. A request for length permits elaborating supplied material; it does not establish the user's qualifications, availability, reasons, attendance dates, completed application or a promise to meet a deadline.
5. Give explicit email framing guidance: use a salutation when the recipient is established, a developed body when requested, and a conventional closing. A clearly identified recruiting organization can supply an addressee; a third-party name or account label cannot establish the user's signature. Use supplied identity only, and preserve body-only instructions. Chat retains its own natural form.
6. Apply chronology and qualification checks to replies as well as summaries. Distinguish a requested action, a reported action and a verified outcome. Where a later response's referent is uncertain, retain that uncertainty rather than declaring either completion or a current blocker.
7. Select literal excerpts supporting the subject and material claims used in the draft. Verify source coverage and final output separately. The model's reported excerpts remain claims for human review.

Start with explicit positive instructions and a short final-output check. Add invented examples only if the instruction-only candidate fails repeatedly; then test the examples as a separately labeled revision. Examples must use unrelated subjects and names, and must not encode answers from these Gmail or Slack scenes. This follows the official guidance to separate instructions, examples and context while evaluating the chosen model on the actual workload. [OpenAI prompt engineering](https://developers.openai.com/api/docs/guides/prompt-engineering#message-formatting-with-markdown-and-xml), [GPT-6 prompting guidance](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices).

**Controlled calibration before changing the live trial**

Create a case manifest and rubric before generating candidates. For each case, annotate the correct composer/conversation, readable source facts, relevant source purpose, required output features, optional details, forbidden claims and expected abstention. Link facts to their visible source location. Do not require a fact that is offscreen, even if another export from the same conversation shows it.

Use the four new capture/intent pairs plus the earlier LinkedIn internship and Slack permissions pairs: six saved cases across five conversation families. Replay each three times under V4 and three times under the instruction-only candidate: 36 total calls. Randomize condition order where practical; retain exact input hashes, actual model, effort, prompt/validation version, timing, usage and failures. Historical V4 outputs supplement these fresh baselines but do not replace them. Plan preparation itself makes no provider calls.

For the Gmail family, add separately labeled controlled intent variants on one identical image: a brief acknowledgement, a full detailed email, and a request to identify the visible subject/main request and quote its support. These distinguish permitted brevity from failure to recover source information. Include a required offscreen-fact variant with an expected abstention. They remain calibration variants of one family, not independent scenes.

Use the existing synthetic composer swaps and language/missing-context controls as regression checks. Expand [the scorer](/Users/itsuki/Desktop/key/laptop/scripts/visual-intent-score-screening.py) to report separate manual dimensions: association, source accuracy/coverage, intent/stance, format/detail, material qualifications/chronology, unsupported claims, abstention and sendability. Human review should determine whether longer text is meaningful; character count can flag a three-line answer but cannot establish quality. Compare drafts without condition labels where possible. This reflects OpenAI's recommendation to define objectives, datasets and criteria before comparing runs, and calibrate scoring with human judgment. [Evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices).

**Diagnostics if the candidate still fails**

| Controlled result | Interpretation and next action |
| --- | --- |
| Source-purpose diagnostic is accurate, but the draft remains generic or ignores requested structure | Focus on composition semantics; test one revised instruction/example policy. An extraction adapter has no demonstrated benefit here. |
| Source-purpose diagnostic misses readable material | Supply a manually verified transcript of only the same visible source text as an explicitly labeled diagnostic input. Retain the same image, composer scope, intent and model. This tests whether access to accurate text improves the draft. |
| Verified visible text corrects the failure | Prototype the existing architecture's B challenger: local Vision OCR observations from the original image, with text/boxes/provenance and composer text excluded. Keep visual ownership binding. Compare against image-only on identical scenes and measure recognition errors, association errors and latency. Add bounded AX observations only as a subsequent isolated test if needed. |
| The image and verified text both yield poor drafts | Compare model capacity or a supported reasoning setting on the same input and settled prompt, through the research gateway. Confirm current compatibility before the run. Use the existing stronger baseline diagnostically; decide production routing only after quality and economics are measured. |
| The requested source is clipped or offscreen | Ask the user to reveal the required part and take a fresh capture. OCR cannot recover absent pixels. Background memory, automatic scrolling and integrations require separate evidence and scope. |

Small Japanese text remains a plausible risk even when it is readable to a person. OpenAI documents limitations involving non-Latin text, small text, resizing and precise localization. If the transcript diagnostic implicates vision, test image readability settings or an enlarged source view as a separate condition, preserving enough full-window context for ownership. Do not initially crop to a presumed email region and treat that as proof of correct association. [Vision limitations](https://developers.openai.com/api/docs/guides/images-vision#limitations).

OpenAI also records a September 25 fix for GPT-6 Luna/Sol image encoding and recommends rerunning affected evaluations. The inspected fresh captures occurred after that date. This does not establish that the known bug caused these failures; provider/model changes are another reason to run fresh paired conditions rather than relying only on old outputs. [OpenAI changelog](https://developers.openai.com/api/docs/changelog).

**Advancement criteria and user testing**

Retain the [architecture decision's prototype gates](/Users/itsuki/Desktop/key/laptop/docs/reports/intent-context-prototype-decision.md): zero observed wrong-conversation replies or material unsupported claims, at least 90% useful grounded drafts on answerable trials, and at least 90% appropriate abstentions on deliberately insufficient trials. Report raw counts and every dimension by surface and family. These are development gates, not a statistical claim of production reliability.

Before the candidate becomes the active A configuration, it must consistently fulfill the explicit Gmail format/detail request without introducing unsupported personal claims, preserve the earlier language/target controls, and avoid regressions on read-only restrictions and chronological reporting. Use only visible facts when assessing the partly scrolled email. Investigate any critical failure rather than averaging it away.

Freeze the candidate after calibration, then evaluate 16 new conversation families across Gmail, LinkedIn and Slack, three repeats each, as already proposed in the architecture decision. Include long messages, explicit short/detailed instructions, multiple panes, later corrections, quoted material, visible/hidden required facts and competing requests. Do not tune on these cases during the acceptance run; further tuning requires a new held-out set. Capture failures belong in the workflow denominator. Repeats measure consistency and do not create new families.

Measure native capture, request/model and press-to-draft times separately. Retain the provisional five-second p95 press-to-draft target; the prior six-real-replay median provider time of about 6.4 seconds already indicates a latency problem requiring measurement, without establishing a live percentile. Preserve one provider call on the normal path while evaluating challengers.

Measure provider cost per useful accepted draft, including failed requests and retries, alongside cost per raw request. The prior roughly ¥102 per 1000 Luna calls is a historical planning estimate from six repetitions, not the cost of the future detailed-output workload. Larger outputs, OCR inputs, reasoning changes and extra calls must be measured before budgeting. A second extraction or repair call must earn its additional latency and cost through repeatable gains.

**Reviewable deliverables**

The implementation should produce a frozen baseline/candidate source snapshot, case manifest with visibility-aware rubrics, raw independent outputs, multidimensional grades and paired findings. Prompt/auth/serialization tests should validate request boundaries; generated-output review should validate semantic quality. If the candidate qualifies for the A trial, verify the deployed source and returned version metadata and update the testing guide. Preserve these user exports as immutable calibration evidence.
