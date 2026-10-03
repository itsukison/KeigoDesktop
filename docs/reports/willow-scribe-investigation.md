# Willow Scribe: installed-app context investigation

Investigated September 26, 2026 (America/New_York; September 27 UTC). No KeigoButton implementation changes.

**Answer:** the installed Willow contains an Accessibility extraction system with app-specific adapters **and a separate, server-requestable screenshot transmission system**. The latter captures with ScreenCaptureKit, can annotate the focused input, encodes an image as JPEG/Base64, and submits a screenshot packet. Local Apple Vision OCR also exists. The strongest supported architectural interpretation is **AX/app context plus visual context sent to a cloud service**, with local OCR available as another context path. It is not defensible to describe this version as AX-only or screenshot → local OCR → text-only cloud processing.

**Important limit:** these are directly inspected binary capabilities, not a completed causal test of which channel Scribe uses. Subsequent manual Gmail and Slack trials are recorded in the [live results](willow-scribe/live-results.md). Supplied Slack screenshots show answers about the main-channel topic while the user reports targeting the side thread; a repeat explicitly naming the right thread and token topic also failed. Target selection can fail despite the implemented context capabilities. Fresh capture versus reused context in the repeat is unverified. The initial passive baseline below is separate from these trials. Per-request channels, the server's model, and backend OCR versus multimodal reasoning remain unverified.

**Manual-test update:** the subsequent native Slack step correctly matched the intended thread. LinkedIn missed a requested clipped opening, then matched concrete details after the opening was scrolled into view. This supports visibility-sensitive recovery, not proof of screenshot-only capture. Changed prompts/layouts/sessions prevent causal attribution to a particular acquisition API. These tests establish both practical capability and failure cases; they do not establish reliable full-thread understanding.

## Evidence labels

- **Directly observed — static:** bytes, metadata, imports, reflection fields, or identified instruction sequences in the installed executable. Establishes implemented capability, not execution during a particular user request.
- **Directly observed — runtime/UI:** process/traffic/file metadata or the current System Settings UI. Establishes the observation, not necessarily its cause.
- **Strongly inferred:** an architectural interpretation supported by multiple independent observations.
- **Speculative:** a plausible explanation requiring a controlled experiment or server-side evidence.

Public documentation is labeled as a vendor claim, not independent runtime verification.

## Scope and reproducibility

The examined executable is `/Applications/Willow Voice.app/Contents/MacOS/Willow Voice`:

| Property | Directly observed value |
|---|---|
| App version/build | 2.5.1 / 2.5.1 |
| Bundle ID | `com.seewillow.WillowMac` |
| Architectures | arm64 and x86_64; instruction analysis used arm64 |
| Executable SHA-256 | `a9921e816f2f45da9aa9fb5ae7f0afa41c01d15ac0e58e60577da6d56a9add3e` |
| Signature | Developer ID, team `B9LTMN6KAW`, hardened runtime flag |
| Signature timestamp | September 25, 2026, 02:01:34 local as printed by `codesign` |
| Minimum macOS | 14.0 |
| Build SDK | macOS 26.5; Xcode 26.6 |
| Investigating host | macOS 26.5, build 25F71 |

This supersedes conclusions based solely on the 2.3.10 inspection recorded in KeigoButton's AGENTS.md. This report does not revise that architectural file.

Methods: `plistlib`, `codesign -d`, `otool -L/-ov`, `nm`, `strings`, read-only `llvm-objdump`, Swift reflection-field parsing, `ps`, `lsof`, `nettop`, filtered unified logs, and read-only navigation of System Settings. Addresses below are **unslid arm64 virtual addresses in this exact build**, not runtime addresses. Most application function names are stripped; Objective-C selectors and Swift reflection metadata survive. A resolved selector at a call site is stronger evidence than an isolated string.

No debugger was attached. No injection, patching, resigning, entitlement alteration, TLS interception, proxy installation, certificate changes, credential access, TCC database access, browser profile/session access, or service requests were performed. Network/cache databases were observed by size/mtime only, not opened. A conventional preferences plist was checked only for six allowlisted feature flags; none were present under those names. Its other values were not reported or used.

Temporary analysis files are in `/tmp/willow-scribe-research/`. The repository evidence companion retains only relevant excerpts and metadata, not the executable or its full disassembly.

## 1. Bundle, frameworks, and helpers

**Directly observed — static:** the main executable links `ApplicationServices`, `ScreenCaptureKit`, `Vision`, `CoreGraphics`, `ImageIO`, `AppKit`, `Foundation`, `Network`, `CFNetwork`, `AVFoundation`, `AVFAudio`, `CoreAudio`, `NaturalLanguage`, `AuthenticationServices`, and others. Relevant embedded frameworks are `whisper`, `YbridOpus`, `YbridOgg`, `Sparkle` 2.9.2, and `Sentry`. Resource bundles also identify Alamofire, PostHog, GoogleSignIn/AppAuth, and image/UI dependencies.

**Directly observed — static:** the helper applications/XPC services found are Sparkle's `Updater.app`, `Downloader.xpc`, and `Installer.xpc`. Duplicate paths through `Versions/Current`/framework symlinks are not independent helpers. No separate Scribe capture helper, browser extension app extension, or Electron renderer bundle was found in the installed bundle inventory.

**Strongly inferred:** screen/AX acquisition is implemented inside Willow's native application process, using Apple services/frameworks, rather than requiring a separately installed browser extension. Absence of a bundled helper does not exclude OS-managed service processes or an optional external integration.

**Directly observed — static:** the entitlements include:

```
com.apple.security.automation.apple-events = true
com.apple.security.automation.control-application = true
com.apple.security.device.audio-input = true
com.apple.security.files.user-selected.read-write = true
com.apple.security.network.client = true
```

Application/team identifiers and Keychain access groups are present. `com.apple.security.app-sandbox` is absent. An entitlement is not a TCC permission grant and does not prove a feature uses it.

Info.plist describes Accessibility as needed for pasting, Apple Events as automation for pasting, and the microphone as needed for transcription. It also has a network-volumes usage string. These descriptions do not fully specify the context architecture; actual AX extraction and screenshot call sites provide stronger evidence.

## 2. Actual permission state on this Mac

Read from System Settings → Privacy & Security; **no switches were changed**:

| Permission | Directly observed — UI | Architectural interpretation |
|---|---|---|
| Accessibility | Willow Voice listed, on | AX extraction, focused-control discovery, and insertion have access. Imports/call sites independently establish those capabilities. |
| Screen & System Audio Recording | Willow Voice listed, on in the screen-recording group | Screenshot acquisition has a current UI grant. Does not establish that Willow records continuous video or system audio. |
| Microphone | Willow Voice listed, on | Supports voice input; separate from contextual screen reading. |
| Automation | Willow absent from the displayed six-app list | No Willow Automation grant was visible. The signed entitlement and usage string alone do not establish dependency. |
| Input Monitoring / Speech Recognition / Remote Desktop | Category counts were zero | No grants shown in these categories; not separately required evidence for Scribe's capture path. |

**Directly observed — static:** imports include `CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess`. App strings include a distinct `scribeScreenContextEnabled` feature, a screen-context permission model, a grant watcher, and screen-recording Settings routes. The UI copy offers continuing without screen context. Therefore capture permission is a separately handled capability, not merely an incidental linked framework.

**Strongly inferred:** Automation/Apple Events is not the primary context acquisition mechanism in the installed configuration. No imported AppleScript/OSA/AE execution entry points were found in the examined main-executable symbol search. Dynamic lookup remains possible; a successful trial with the currently absent Automation listing would provide better causal evidence.

Do not interpret the lack of `NSScreenCaptureUsageDescription` or a screenshot-specific entitlement as absence of screen capture. The concrete ScreenCaptureKit calls and TCC UI are the relevant evidence.

## 3. The visual channel: screen image → network packet

### Implemented capture

**Directly observed — static:** `ScreenshotCaptureService` and these reflection fields survive:

```
CaptureSource:
  applicationBundleIdentifier, applicationProcessID,
  mainDisplay, focusedApplication, focusedWindow
CapturePlan:
  filter, contentRect, pointPixelScale, annotationScreenRect, legacyTarget
CapturedImage:
  image, contentRect, pointPixelScale, annotationScreenRect
ScreenshotCommandOptions:
  source, annotateFocusedTextField, pixelsPerPoint, pixelsPerInch, showsCursor
```

These describe several supported scopes, not proof of the scope used by every Scribe request.

**Directly observed — static call sites:**

| Address | Identified operation |
|---|---|
| `0x1000bec48` | `SCContentFilter.initWithDesktopIndependentWindow:` |
| `0x1000be9f8` | Display filter excluding applications |
| `0x1000c0f88` | Display filter including applications |
| `0x1000c12b4` | `SCShareableContent.infoForFilter:` |
| `0x1000c12c8`, `0x1000c12f0` | Read content rectangle and point/pixel scale |
| `0x1000c1430`, `0x1000c149c` | Set screenshot width/height |
| `0x1000c14a8` | Configure whether the cursor is shown |
| `0x1000c14d0`, `0x1000c14dc` | Configure display/single-window shadow handling |
| `0x1000c1700` | `SCScreenshotManager.captureImageWithFilter:configuration:completionHandler:` |

Nearby code enumerates applications/windows, compares process IDs, checks `isOnScreen`/`isActive`, and intersects/unions rectangles. This is substantially more specific than a generic “take the main display” implementation. The default server-requested scope was not conclusively reconstructed.

Apple documents the screenshot API as individual-frame capture; use of it does not imply a persistent screen recording. [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)

### Focus annotation

**Directly observed — static:** the capture region contains AX position/size reads and a parameter named `annotateFocusedTextField`. Later image-processing code obtains `systemRedColor`, sets stroke color/line width, and calls `CGContextStrokeRect` (`0x1000c28bc`), followed by additional path drawing. `annotationScreenRect` is carried alongside the captured image.

**Strongly inferred:** Willow can mark the intended input field on the screenshot, giving the receiving visual interpreter a target cue. This is especially relevant when several threads or composers are visible. It is not verified that annotation is enabled on every request or that the additional path represents a particular arrow shape.

### Server request and image serialization

**Directly observed — static:** the command-dispatch block references “Server requested screenshot — capturing and sending” at `0x10007d174`, parses screenshot options, and invokes the screenshot scheduling path at `0x10007d224`. Other code handles unknown screenshot sources, unavailable/disabled screen context, capture errors, and empty screenshot responses.

The send path calls image encoding at `0x10006b234`, handles JPEG-conversion failure, calls `Data.base64EncodedString` at `0x10006b30c`, and references “Sending SCREENSHOT packet directly” at `0x10006b36c`. It passes the resulting string into the packet-send path at `0x10006b4c8`. The encoding function uses `CGImageDestinationCreateWithData`, lossy-compression quality, optional DPI properties, `CGImageDestinationAddImage`, and `CGImageDestinationFinalize`.

**Directly observed — static:** the screenshot logging calculation counts the Base64 string and divides by 1024 before logging a rounded KB value. A future log's “KB base64” value must not be mistaken for JPEG bytes or total wire bytes. A screenshot-encoding call constructs floating-point `0.7`; this is consistent with a JPEG quality argument, but is not a measured effective quality for all capture branches. A configuration key `scribe_image_downsample` and a property `_scribeImageDownsampleMegapixels` are also present; their current configured value was not read.

**Strongly inferred:** Scribe supports cloud image processing, not merely uploading locally recognized text. Exactly which backend/model consumes the image remains unknown. Server-side OCR alone, multimodal reasoning, or a combination are all consistent with an image packet. A particular Gemini/OpenAI/Claude model is **speculative**.

## 4. The AX channel and app-specific extraction

**Directly observed — static:** `ACCESSIBILITY_CONTEXT`, `APP_CONTEXT`, selected-text, cursor-before/after, and conversation-history fields exist separately from the screenshot packet. There are distinct queue/send messages for Accessibility and app context. The app-context shape includes application name, bundle ID, window title, URL, cursor context, clipboard text, and AI context. A field's presence is not proof that it is populated or enabled on every request; in particular, clipboard inclusion cannot be assumed.

**Directly observed — static:** the installed executable contains these extractors:

- `GmailExplorer`, `OutlookWebExplorer`, `SuperhumanExplorer`, `GeneralWebExplorer`, `WebExplorerBase`.
- `SlackExplorer`, `MessageExplorer`, `WhatsAppExplorer`, `AppleMailExplorer`, `OutlookExplorer`.
- `ClaudeExplorer`, `CodexExplorer`, `VSCodeExplorer`, `TerminalExplorer`, `DefaultExplorer`.
- `AccessibilityExplorer`, `UIElement`, `ElectronAppManager`.

Message representations include:

```
SlackContextMessage: sender, body
EmailThreadMessage: sender, time, body, contentState
EmailThreadMessage.ContentState: complete, preview
ConversationThreadMessage: role, sender, time, body
```

**Strongly inferred:** Willow does app-aware extraction and represents message boundaries/author information locally rather than relying entirely on a generic flat AX text dump. The explicit complete/preview distinction is particularly relevant to avoiding sidebar previews masquerading as full emails. Extractor names/fields do not establish how accurate each adapter is today. No dedicated `LinkedInExplorer` was found; LinkedIn may use a general web extractor and/or screenshots (**speculative**).

**Directly observed — static:** its AX toolkit includes attribute and parameterized-attribute enumeration, `AXStringForRange`, `AXVisibleCharacterRange`, AX text-marker range APIs, focused-element/window notifications, and messaging timeouts. At `0x10019e374`, code calls `AXUIElementCopyParameterizedAttributeValue` after constructing `AXStringForRange`. The binary also contains AX DOM identifier/class attribute names. Reading these through AX does not require executing browser JavaScript.

**Directly observed — static:** at `0x1001af8e8` and `0x1001af938`, code sets `AXEnhancedUserInterface` and `AXManualAccessibility` to true on an application AX element. Another branch sets `AXManualAccessibility` separately. `ElectronAppManager` carries an `accessibilityQueue`. The complete app-eligibility/retry policy was not reconstructed.

Electron publicly documents `AXManualAccessibility` as an external way to activate its accessibility support. The additional enhanced-UI attribute merits controlled testing before adopting it; Willow's use does not make it harmless or necessary everywhere. [Electron documentation](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md)

## 5. Local OCR exists, but its Scribe role needs care

**Directly observed — static:** `OCRManager` stores `currentCaptureContextId`, `currentOCRImage`, `currentOCRText`, and `currentOCRGlossary`. `ResultManager` and the transcription pipeline reference it.

Identified code constructs `VNImageRequestHandler` from a CGImage (`0x1000a7be4`), allocates `VNRecognizeTextRequest` (`0x1000a7c04`), sets its recognition level (`0x1000a7c18`), performs requests (`0x1000a7708`), and retrieves observations, top candidates, and strings (`0x1000a7f24`–`0x1000a8090`). The recognition-level argument is zero, corresponding to accurate recognition in the installed SDK header (`VNRequestTextRecognitionLevelAccurate = 0`).

**Strongly inferred:** local OCR provides recognized text and/or terminology for contextual dictation. The `context_glossary` packet and separate ordinary context-awareness setting support this interpretation. It may also assist Scribe, but presence in a shared pipeline is insufficient to prove an obligatory OCR-before-Scribe sequence.

**Not established:** OCR language configuration, preservation of OCR boxes in the request, OCR execution frequency, and whether Scribe runs this OCR path when it already uploads a screenshot. These must not be borrowed from assumptions about the older Willow build.

## 6. Runtime evidence and its limits

**Directly observed — runtime:** Willow was running as PID 31817, parent PID 1. The bundle-specific process samples initially showed only the main app, with no separately named Willow context helper. Sampling at intervals can miss a short-lived helper; OS services are not ruled out.

Passive observations recorded independent per-process network counter snapshots (not integrated transfer totals), current socket metadata where available, and size/mtime of Willow's `async.log`, `Cache.db`, and `Cache.db-wal`. No database contents, request bodies, audio, or screen images were read. The final bounded observation summary is in [the evidence companion](willow-scribe/evidence.md).

**Directly observed — runtime:** the open `async.log` was empty during inspected samples. Unified logs were present, mostly Apple network, audio, and UI infrastructure events. Filtering for the screenshot/AX packet event names did not produce a correlated Scribe trace. The disassembly shows some interesting event strings being placed into Sentry breadcrumbs; their absence from unified logs therefore does not establish that a path did not execute. Sentry's stored data was not opened.

**Directly observed — runtime:** network counters changed and the HTTP-cache write-ahead log changed. No user-confirmed trigger marker identifies those changes as Scribe. Updates, account refresh, analytics, normal dictation, or other background work can contribute. `lsof` sampling did not expose live network endpoints in these samples. Static hostnames such as `api.willowvoice.com` and `middleware.willowvoice.com` are configuration evidence, **not observed request destinations**.

**Unverified:** screenshot payload bytes, request count, precise transport timing, new processes during Scribe, and temporary screenshot files during a confirmed Scribe request. An image can stay entirely in memory, so absence of PNG/JPEG files would not refute image capture. No privileged filesystem trace or packet sniffer was used, and no TLS payload type was inferred merely from traffic volume.

### Expected payload forms, not measured payloads

| Channel | Evidence-supported form | What remains unknown |
|---|---|---|
| Screenshot | JPEG → Base64 string → screenshot packet | Actual dimensions, image size, frequency, cloud consumer |
| AX context | Separately serialized context packet | Exact per-app populated content and size |
| App context | Structured application/window/cursor fields | Which optional fields are enabled per request |
| Voice | Audio-related packet types and Opus/Ogg/audio frameworks | Actual encoding/rate for a given Scribe session |

The binary contains a WebSocket transport, packet chunking/reassembly types, and MessagePack encoding/decoding diagnostics. **Strongly inferred:** a multiplexed transport carries control/audio/context messages, rather than every screenshot necessarily becoming a separately visible HTTP upload. This is why byte-count observation must separate voice duration and baseline traffic.

For planning only: a 200 KiB JPEG becomes approximately 267 KiB of Base64 before packet/TLS overhead. This is arithmetic, **not a Willow measurement**. Encrypted traffic size cannot distinguish an image from a larger text/audio payload reliably.

## 7. Controlled experiments to finish causal attribution

The [local test fixture](willow-scribe/fixture.html) is a synthetic communication page with an editable reply field and no Send action. It makes no network requests. It supports normal DOM text, canvas-only text, conflicting visual/AX text, and a color-dependent visual selection task. Use a normal external browser so Willow sees the same browser surface it normally operates on. Fresh cases generate new canaries; the correct canary is not shown elsewhere in the UI. The fixture is prepared, not yet exercised with Willow.

**The controlled matrix below remains proposed.** Initial manual Gmail and Slack workflow observations are recorded separately in the [live results](willow-scribe/live-results.md); the permission and representation contrasts have not been completed. Have the user trigger Scribe and change Willow's permissions manually. Record the original permission/settings state and restore it afterward. Never change permissions belonging to Codex, the browser, or KeigoButton as part of Willow's matrix.

### A. First: normal workflow, with existing permissions

Run one synthetic/non-sensitive case each in Gmail, Slack, and LinkedIn. Record browser versus native Slack, app versions, thread visible area, focused composer, exact trigger/finish time, spoken B, generated output, and whether a unique fact only present in A was recovered. Use a fresh canary such as a meeting location/code that B does not repeat. Do not send the result to anybody.

Begin with the user's real Scribe shortcut; keep each spoken request approximately the same duration. Mark each start/stop in the observer's timeline. Collect an idle interval before and after. Keep System Settings and our own inspection UI out of the foreground during the trial.

### B. Permission matrix

| Willow AX | Willow Screen Recording | Best diagnostic value |
|---|---|---|
| On | On | Normal capability; does not separate sources. |
| On | Off | Success with fresh DOM-only facts supports AX/other nonvisual context. Compare canvas facts. |
| Off | On | If Scribe still starts and drafts into its own preview, success with canvas facts supports visual acquisition. Failure is ambiguous because AX may gate invocation, focus capture, or insertion. |
| Off | Off | Control for facts supplied by B, prior turns, clipboard, or other retained context. Successful writing alone does not demonstrate screen reading. |

Also compare **Willow's own Scribe screen-context toggle off/on while macOS permissions stay on**. This isolates its application policy from OS permission behavior. A toggle may disable both AX and images; do not assume it switches only screenshot capture. If macOS asks to quit/reopen Willow, let the user do so and use fresh test data after restart. Do not interpret stale grants/cached context as a successful ablation.

### C. Distinguish representations

1. **DOM vs canvas, same layout/content, new canary each run.** A canvas must have no textual fallback/ARIA copy of the canary; verify its AX tree independently. Canvas success strongly rejects AX-only reading of the source text, but cannot distinguish local OCR from cloud vision.
2. **Contradictory visual and AX canaries.** In the fixture's conflict case, the visible card is canvas; its separate AX label supplies a different code. First verify the browser actually exposes the AX label. Ask for the code on the card. Which code appears in the answer is evidence of precedence, not proof that the other channel was absent. Counterbalance codes/order and use multiple runs.
3. **Non-text visual relation.** Two canvas cards have randomized positions and different codes; only one has a green dot. Ask for the code on the green-dot card. Successful selection needs information beyond an ordinary text-only OCR transcript. A local image analyzer could also supply color/geometry, so this supports a visual representation but does not identify a particular cloud model.
4. **Onscreen/offscreen/collapsed content.** Put different fresh facts in the visible body, a scrolled-off previous message, and a collapsed quote. Verify which are AX-exposed. Compare results to distinguish screenshot visibility from AX history reach. Never conflate recovered preview text with the complete thread.
5. **Two conversations/composers.** Keep conflicting facts in main-pane and side-thread messages; focus each composer in turn. Success tests the utility of target annotation and scope selection, not just raw text recognition.
6. **Before/during trigger timing.** Show one canary, replace it immediately before or during Scribe activation, and use a fresh Scribe session. Repeat while idle versus dictating. Old-fact recovery could indicate an earlier capture, retained conversation, or memory; it is not by itself proof of rolling background screenshots.
7. **Browser/native and app adapters.** Repeat matched fixtures in native Slack versus Slack web, and compare app-specific Gmail against a plain local page. Similar visual success but different no-screen-permission behavior would support an AX adapter advantage. App version/layout must be controlled.

The installed UI string says capture occurs while dictating, not in the background. That is **directly observed UI copy**, not a runtime guarantee. `currentOCRImage` is also not evidence of a rolling historical screen cache.

### D. Local OCR versus cloud image processing

The static JPEG/Base64 packet path already establishes an implemented cloud-image capability. The remaining question is whether it executes in each case.

- Correlate a user-triggered case with available screenshot packet-size diagnostics, if Willow exposes them through normal logs. Do not enable hidden debug/upload flags or open stored session data.
- Observe CPU/process activity and, if ordinary macOS permissions allow, a brief `sample` during a synthetic test for Vision or ScreenCaptureKit frames. No injection or memory dump is needed; missing a short async frame is not evidence of absence.
- Compare equal-duration voice requests with image complexity/dimensions varied. A repeatable extra upload cost is supportive, not proof of payload identity.
- An offline test primarily tests Scribe's generation dependency. Failure offline cannot prove that capture/OCR was not local. The binary itself distinguishes offline dictation from Scribe needing internet.
- Strongest attainable conclusion without decrypting traffic or inspecting the service: annotated-image upload supported by static tracing plus correlated runtime diagnostics/visual-only behavioral success. Backend OCR versus multimodal reasoning may remain unresolved.

A result ledger should include: case ID; fresh canary; app/version; AX grant; screen grant; Scribe toggle; visible/AX source details; start/stop time; output; factual success; invocation/insertion failure separately; network deltas from a continuous interval-logging run and its idle baseline; relevant diagnostic labels. Perform at least three fresh repetitions for decisive contrasts, counterbalanced in order.

## 8. What Willow appears to do differently from KeigoButton

This compares directly observed Willow capabilities with the code and failures in [our previous architecture investigation](no-extension-context-architecture.md). It does not claim Willow is more reliable without matched trials.

| Area | KeigoButton today / parked experiment | Willow evidence | Implication for later design |
|---|---|---|---|
| Shipping capture | Copy-to-reply; automatic capture hard-off | Separate screen-context permission and implemented image/AX channels | Evaluate a new explicit capture capability; no release change justified by this report alone. |
| Visual fallback | No active screenshot context path | ScreenCaptureKit + JPEG/Base64 screenshot packets | Missing AX text need not terminate contextual composition. |
| Target binding | Focus-first AX traversal and geometry | Focused-window/app capture plus optional field annotation | Prototype a clearly marked composer on a scoped image. |
| Conversation structure | Generic normalization can fragment email bodies; one nearby unread node can reject capture | App-specific extractors; sender/body/time and complete/preview types | Distinguish message completeness from generic node completeness. |
| AX activation | `primeManualAccessibility`, cached attempt, immediate read | Both manual/enhanced attributes in app-conditioned code | Test readiness and activation in an isolated harness; do not blindly copy private attributes. |
| AX reading | Conversation reader primarily pages `AXChildren` | Parameterized ranges, text markers, notifications, app helpers | Broaden missing capabilities where data demonstrates value. |
| Capture orchestration | Predominantly capture → interpret → generate | Server-requestable screenshots alongside queued AX/app context | Compare one-shot screenshot+B against hybrid and optional adaptive recapture. |
| Local OCR | Proposed in our previous report | Implemented Vision OCR and context glossary | Useful capability, but not proof OCR must be a mandatory stage before writing. |

The current code reference points are [AXConversationReader](../../Sources/TextIO/AXConversationReader.swift), [ConversationTraversal](../../Sources/TextIO/ConversationTraversal.swift), [AXTextIO](../../Sources/TextIO/AXTextIO.swift), and [the disabled feature gate](../../Sources/DesktopRewriteKit/Reply/ReplySession.swift).

**Strongly inferred:** Willow has an architectural capability advantage in multiple evidence channels, application-specific structure, and target-aware screenshots. Improved end-to-end reliability is not established: the manual Slack trial produced a wrong-conversation answer. There is no evidence that its answer is simply “traverse AX deeper.” There is also no evidence that it requires a generic reconstructed accessibility tree or a separate Jev-like relevance stage.

**Recommendation, not an implementation change:** prioritize testing the simple focused-window screenshot + B baseline, optionally marking the composer and adding exact AX text when available. Compare against local OCR + B and hybrid representations on the same cases. Keep Jev optional until it demonstrates incremental selection value. Willow strengthens the case for that experiment; it does not settle its latency, privacy, scope, or accuracy tradeoffs for KeigoButton.

## 9. Final classification

**Directly observed:** AX and Screen Recording are enabled for Willow; no Automation listing is visible; the installed binary implements app-specific AX context extraction, local Vision OCR, configurable ScreenCaptureKit screenshots, focus annotation, and JPEG/Base64 screenshot packet transmission, including server-requested capture. These are distinct observations with explicit static/runtime boundaries.

**Strongly inferred:** Scribe's surrounding context can come from app-aware AX text **and captured screen images sent to Willow's cloud pipeline**. Local OCR is another available path, likely connected to contextual terminology/dictation. Screen images give the architecture a way around missing browser/Electron AX content.

**Speculative / still unresolved:** the path actually chosen per Gmail/Slack/LinkedIn request; screenshot fallback versus unconditional capture; exact source scope/default timing; backend OCR versus a multimodal model; provider/model name; screenshot retention; optional screenshot artifact-upload behavior; rolling context cache; and comparative reliability. These require the manual experiments or information outside the installed client. No retained-session or server data was inspected to answer them.

Willow's public Scribe guide describes intent-based replies using screen context. Its privacy policy acknowledges transient cloud processing and distinguishes it from retention. Those statements are compatible with the observed client architecture, but do not independently establish what any particular request transmits or retains. [Scribe guide](https://help.willowvoice.com/en/articles/15043797-introduction-to-scribe-in-willow), [privacy policy](https://willowvoice.com/privacy-policy).
