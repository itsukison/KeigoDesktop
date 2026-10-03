# Manual Willow trials

These observations extend the installed-app investigation. The user operated Willow. No permissions were changed by the investigator, and no messages were sent by the investigator. Tests have not yet isolated AX versus visual acquisition.

## Evidence classification

**Directly observed in the supplied Slack screenshot:** two conversation panes and two composers are present. The right-hand thread discusses reducing AI usage costs. The latest visible main-channel message discusses overlapping Amazon discounts and points. Willow's generated answer describes the Amazon problem and proposes API-based detection and compensation. The displayed instruction asks for a solution to “this problem” without naming either topic.

**User-reported:** the right-hand thread composer was focused when Willow was invoked. This focus state was not independently captured before invocation; the attached screenshot shows the result afterward. The test followed the planned Slack web step, but the screenshot alone does not establish browser versus native client.

**Strongly inferred:** Willow produced an answer about the wrong conversation for the reported target. This is evidence of an end-to-end target-binding failure, even though its answer is relevant to another visible message. Recovering plausible screen content is insufficient for the product goal.

**Speculative:** the underlying failure could be incorrect capture scope, both conversations being extracted without enough target information, stale focus, a target annotation not used or not understood, or generation favoring the latest main-channel message. This trial does not identify the representation or stage responsible. The existence of focus-annotation code does not establish that it ran here or worked.

Screenshot evidence: user attachment `Screenshot 2026-09-26 at 23.41.27.png`, September 26, 2026, 23:41:27 EDT. The original attachment remains in the conversation; no additional copy of the workplace screenshot is stored in this report.

**Directly observed in a second supplied screenshot:** at 23:44:46 EDT, the displayed instruction explicitly identifies the thread on the right and mentions tokens. The instruction is truncated, so its full wording is not verified. The generated answer again discusses overlapping discounts and points and proposes API checks, matching the main-channel topic rather than the token-cost thread.

**Strongly inferred:** explicit spatial and topical guidance did not resolve the wrong-conversation result in this repeat. This weakens the explanation that the first prompt merely needed clearer wording. **Unresolved:** whether this was a fresh Scribe invocation or a refinement retaining the earlier capture, whether the thread was included in captured evidence, and whether selection or generation ignored available thread evidence. It does not prove that the thread was inaccessible to AX or absent from an image.

**Directly observed in the third supplied screenshot:** at 23:46:35 EDT, following the instruction to test native Slack, the answer refers to Cowork usage around $7,500 and prioritizing restrictions there rather than across all settings. Both details appear in the right-hand thread. The competing Amazon message remains visible in the main channel. This is a successful target-topic and concrete-detail match. The displayed spoken instruction is truncated, so recovery of facts absent from the full spoken request has not been independently established. The proposed remedies in the generated answer are not all verified source facts.

**Strongly inferred:** Willow can use the intended thread in this configuration; failure is not universal to two-pane Slack. **Speculative:** a native Slack AX adapter explains the difference. Client identity follows the requested test sequence rather than independent process verification; viewport, capture session, and wording also differ. This is not a controlled demonstration that native AX outperforms browser AX or that one trial used screenshots and another used AX.

**Directly observed in the LinkedIn screenshot:** at 23:50:00 EDT, the message opening is above the visible portion. The displayed instruction requests both the proposal and the beginning of the conversation, although its ending is truncated. The generated answer references Boston Career Forum 2026 and SoftBank recruiting, both explainable from visible message/signature information. It also describes the opening as introducing global career opportunities, which cannot be verified against the hidden opening from this screenshot.

**User-reported:** the answer did not mention the actual clipped opening. **Strongly inferred:** this trial did not demonstrate recovery of the requested offscreen detail; the observed reply can be explained by visible content and inference. **Speculative:** screenshot/OCR-only acquisition caused the limitation. An AX extractor could also restrict itself to visible nodes, the application could omit offscreen content from AX, or generation could omit supplied evidence. Neither the hidden text nor its AX exposure was inspected, so this result does not distinguish those explanations.

**Directly observed in the follow-up LinkedIn screenshot:** at 23:52:33 EDT, the opening is visible and the output refers to Core7 AI software development, more than 5,000 users, and TikTok Shop's Japan expansion. These details match the newly visible opening. The displayed instruction asks to acknowledge specific things the sender said about the user; it is truncated and differs from the previous instruction.

**Strongly inferred:** visibility affects the context recovered in this workflow. The earlier miss followed by a concrete match after scrolling is useful behavioral evidence. **Limit:** this is a single, non-counterbalanced pair with changed wording and a new invocation; it does not isolate scrolling as the cause, prove source-exclusive recovery from the full unobserved spoken request, or distinguish screenshots/local OCR from visibility-filtered AX. It is evidence against assuming that Willow reliably obtains the entire LinkedIn message irrespective of viewport.

## Trial ledger

| Trial | Evidence | Result and limit |
|---|---|---|
| Gmail 1 | User asked to agree; reported a generic Japanese agreement | Generation worked; no source-only detail demonstrates contextual reading. |
| Gmail 2 | User reported a reply about rough intention versus polishing; clarified this was email, not Slack, and the email was not fully visible | Suggestive of context use; no verified fresh source-only fact or visibility boundary. Does not demonstrate offscreen reading. |
| Slack, two panes | User screenshot plus reported focus on right-hand thread | Wrong-conversation answer: main-channel Amazon topic instead of thread AI-cost topic. |
| Slack, explicit thread instruction | Second screenshot names the right thread and token topic in the displayed instruction | Same wrong-topic result despite explicit guidance. Fresh capture versus reused context not verified. |
| Native Slack step | Third screenshot matches right-thread Cowork usage and roughly $7,500 cost | Successful topic/detail match while competing channel message remains visible. Full prompt and exact mechanism unverified. |
| LinkedIn, clipped opening | Fourth screenshot plus user report that actual opening was missed | Reply uses visible recruiting details; offscreen-detail recovery not demonstrated. Hidden opening and AX availability unverified. |
| LinkedIn, opening visible | Fifth screenshot matches Core7, over 5,000 users, and TikTok Shop details | Concrete match after scrolling; supports visibility dependence, with prompt/session changes as confounds. |

The second Gmail test was initially mislabeled Slack web in the working notes and has been corrected. Initial Gmail, Slack web, native Slack, and LinkedIn workflow observations are now collected; causal permission/representation tests remain incomplete.

## Runtime correlation

A new bounded observer began at `2026-09-27T03:29:17.389574Z` (23:29:17 EDT), with a 30-minute maximum. It collects bundle-specific process samples, continuous per-process network deltas, socket metadata where available, and sizes/mtimes of three cache/log files. It does not read cache contents or decrypt traffic. Raw metadata is under `/tmp/willow-scribe-research/live-20260927T032917Z/`.

The observer was stopped at `2026-09-27T03:53:56.834216Z` after 727 metadata samples (about 25 minutes). Both investigator-created monitoring processes were verified exited; Willow was not stopped or changed. The [saved runtime summary](live-runtime-summary.json) retains metadata and 13 deduplicated text-recognition events across the inspected log windows. No allowlisted screenshot/AX packet-send event appeared. No screenshot payload size or provider/model identity was established.

**Directly observed:** traffic bursts occurred during the test session. The first nettop sample is cumulative and is excluded from interval analysis. Later rows are deltas, but file buffering delays availability and rows lack explicit timestamps; no exact upload size is assigned to a particular trial or payload type. The sampled bundle process remained Willow's main process. No socket endpoints appeared in periodic lsof results; short-lived connections/helpers can be missed.

**Directly observed:** logs from the Willow process contain `com.apple.TextRecognition` events, including Recognition/Detection categories at 23:30:34 EDT and General-category events at 23:38:20, 23:38:21, and 23:40:48. No allowlisted screenshot/AX packet-send diagnostic was found in the inspected log windows. Only subsystem/category/timestamp metadata was retained, not message bodies.

**Strongly inferred:** local text-recognition machinery was active during testing, consistent with the statically identified Vision path. **Unresolved:** which pixels were processed, which trial consumed the result, and whether any recognized text was used for reply generation. General-category events alone do not establish a completed OCR request.

## Next discriminating test

The initial LinkedIn hidden/visible comparison is complete and supports visibility dependence with the limits above. A stronger follow-up would hold the instruction constant, use fresh distinctive facts, verify AX exposure independently, and counterbalance visibility order. It would still require permission/representation contrasts to distinguish screenshots from visibility-filtered AX.

For Slack, explicit thread guidance failed in one repeat; the subsequent native step matched the intended thread. Control that browser/native comparison with matched layouts, fresh conflicting facts, alternating focused composers, and fresh captures distinguished from refinements. Permission and representation contrasts are still needed to identify AX versus visual acquisition.

For KeigoButton, keep wrong-conversation rate separate from text-recovery rate. The smallest prototype should preserve a captured target identity and a composer-to-conversation association in its evidence, and include this two-pane case as an acceptance test. A marked full-window screenshot is a baseline to test, not a demonstrated solution.
