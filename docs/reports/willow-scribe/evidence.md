# Willow Scribe: evidence companion

Labels: all binary excerpts below are **directly observed static evidence**, not runtime execution traces. Version, hash, limitations, and interpretation are in [the report](../willow-scribe-investigation.md). Addresses are unslid arm64 virtual addresses for the examined 2.5.1 binary.

## Permission observations

System Settings was read through its UI, without changing switches:

- Accessibility: Willow Voice on.
- Screen & System Audio Recording: Willow Voice on in the screen-recording group.
- Microphone: Willow Voice on.
- Automation: six applications listed; Willow absent.

## Relevant imports

```

```

## Swift reflection fields

Private-context mangling artifacts were omitted from display names; field names were read directly from relative field descriptors.

```
Willow_Voice.TranscriptionPipelineClient..ScreenshotCommandOptions: source, annotateFocusedTextField, pixelsPerPoint, pixelsPerInch, showsCursor
Willow_Voice.OCRManager: currentCaptureContextId, currentOCRImage, currentOCRText, currentOCRGlossary
Willow_Voice.ScreenshotCaptureService:
Willow_Voice.ScreenshotCaptureService.CapturePlan: filter, contentRect, pointPixelScale, annotationScreenRect, legacyTarget
Willow_Voice.ScreenshotCaptureService.CapturedImage: image, contentRect, pointPixelScale, annotationScreenRect
Willow_Voice.ScreenshotCaptureService.CaptureSource: applicationBundleIdentifier, applicationProcessID, mainDisplay, focusedApplication, focusedWindow
Willow_Voice.ScreenshotCaptureService..LegacyCaptureTarget: display, window, windows
Willow_Voice.SlackExplorer: channels, names
Willow_Voice.SlackContextMessage: sender, body
Willow_Voice.GmailExplorer:
Willow_Voice.EmailThreadMessage: sender, time, body, contentState
Willow_Voice.ConversationThreadMessage: role, sender, time, body
Willow_Voice.EmailThreadMessage.ContentState: complete, preview
Willow_Voice.ElectronAppManager: accessibilityQueue
```

## Selected instruction evidence

`SELECTOR` annotations were resolved from the executable’s Objective-C selector stubs. Only selected relevant regions are retained here.

```asm
10006b218:	ldr	x8, [x22, #0xf0]
10006b21c:	ldr	x3, [x8, #0x28]
10006b220:	ldrb	w4, [x8, #0x30]
10006b224:	mov	x0, x20
10006b228:	mov	x1, #0x6666666666666666
10006b22c:	movk	x1, #0x3fe6, lsl #48
10006b230:	mov	w2, #0x0
10006b234:	bl	0x1000c2b34
10006b238:	mov	x19, x0
10006b23c:	mov	x21, x1
10006b240:	mov	x0, x20
10006b244:	bl	0x100ea8a90 ; symbol stub for: _objc_release
10006b248:	stp	x19, x21, [x22, #0x178]
10006b24c:	lsr	x8, x21, #60
10006b250:	cmp	x8, #0xf
10006b300:	mov	x0, #0x0
10006b304:	mov	x1, x19
10006b308:	mov	x2, x21
10006b30c:	bl	0x100ea2a90 ; symbol stub for: _$s10Foundation4DataV19base64EncodedString7optionsSSSo27NSDataBase64EncodingOptionsV_tF
10006b368:	adrp	x8, 3906 ; 0x100fad000
10006b36c:	add	x8, x8, #0x9d0 ; literal pool for: "Sending SCREENSHOT packet directly: "
10006b370:	sub	x8, x8, #0x20
10006b374:	add	x0, x25, #0xe
10006b378:	orr	x1, x8, #0x8000000000000000
10006b37c:	bl	0x100ea5430 ; symbol stub for: _$sSS6appendyySSF
10006b380:	mov	x0, x19
10006b384:	mov	x1, x21
10006b388:	bl	0x100ea53dc ; symbol stub for: _$sSS5countSivg
10006b38c:	scvtf	d0, x0, #0xa
10006b390:	frinta	d0, d0
10006b394:	adrp	x1, 4549 ; 0x101230000
10006b398:	ldr	x1, [x1, #0xd98] ; literal pool symbol address: _$ss26DefaultStringInterpolationVN
10006b39c:	adrp	x2, 4549 ; 0x101230000
10006b3a0:	ldr	x2, [x2, #0xda0] ; literal pool symbol address: _$ss26DefaultStringInterpolationVs16TextOutputStreamsWP
10006b3a4:	mov	x0, x20
10006b3a8:	bl	0x100ea5a0c ; symbol stub for: _$sSd5write2toyxz_ts16TextOutputStreamRzlF
10006b3ac:	mov	x0, #0x424b
10006b3b0:	movk	x0, #0x6220, lsl #16
10006b3b4:	movk	x0, #0x7361, lsl #32
10006b3b8:	movk	x0, #0x3665, lsl #48
10006b3bc:	mov	x1, #0x34
10006b3c0:	movk	x1, #0xe900, lsl #48
10006b3c4:	bl	0x100ea5430 ; symbol stub for: _$sSS6appendyySSF
10006b468:	adrp	x8, 4548 ; 0x10122f000
10006b46c:	ldr	x8, [x8, #0xfb0] ; literal pool symbol address: _$sSSN
10006b470:	str	x8, [x22, #0x98]
10006b474:	mov	x23, x22
10006b478:	str	x19, [x23, #0x80]!
10006b47c:	str	x21, [x22, #0x88]
10006b480:	adrp	x8, 3700 ; 0x100edf000
10006b484:	ldr	w0, [x8, #0xff4]
10006b488:	bl	0x100ea95e8 ; symbol stub for: _swift_task_alloc
10006b48c:	str	x0, [x22, #0x190]
10006b490:	adrp	x8, 0 ; 0x10006b000
10006b494:	add	x8, x8, #0x8dc
10006b498:	stp	x22, x8, [x0]
10006b49c:	ldr	x20, [x22, #0xe8]
10006b4a0:	mov	x22, x0
10006b4a4:	mov	w0, #0xb
10006b4a8:	mov	x1, x23
10006b4ac:	ldp	x29, x30, [sp, #0x50]
10006b4b0:	ldp	x21, x19, [sp, #0x38]
10006b4b4:	ldp	x24, x23, [sp, #0x28]
10006b4b8:	ldp	x26, x25, [sp, #0x18]
10006b4bc:	ldr	x27, [sp, #0x10]
10006b4c0:	and	x29, x29, #0xefffffffffffffff
10006b4c4:	add	sp, sp, #0x60
10006b4c8:	b	0x10007b5e0
10007b350:	add	x8, x8, #0xd70 ; literal pool for: "Sending ACCESSIBILITY_CONTEXT packet: "
10007d174:	add	x8, x8, #0xa30 ; literal pool for: "Server requested screenshot \342\200\224 capturing and sending"
10007d208:	sub	x8, x29, #0x90
10007d20c:	mov	x0, x22
10007d210:	bl	0x10007fd10
10007d214:	mov	x0, x22
10007d218:	bl	0x100ea9120 ; symbol stub for: _swift_bridgeObjectRelease
10007d21c:	sub	x0, x29, #0x90
10007d220:	mov	x20, x21
10007d224:	bl	0x10006a918
10007d228:	sub	x0, x29, #0x90
10007d22c:	bl	0x100083cb8
1000a7bf4:	str	x19, [sp, #0x20]
1000a7bf8:	mov	x0, x19
1000a7bfc:	bl	0x100ea8a90 ; symbol stub for: _objc_release
1000a7c00:	adrp	x8, 4735 ; 0x101326000
1000a7c04:	ldr	x0, [x8, #0x510] ; Objc class ref: _OBJC_CLASS_$_VNRecognizeTextRequest
1000a7c08:	bl	0x100ea8958 ; symbol stub for: _objc_allocWithZone
1000a7c0c:	bl	0x100eb1600 ; SELECTOR init
1000a7c10:	mov	x24, x0
1000a7c14:	mov	x2, #0x0
1000a7c18:	bl	0x100ebc3a0 ; SELECTOR setRecognitionLevel:
1000be9f8:	bl	0x100eb1fc0 ; SELECTOR initWithDisplay:excludingApplications:exceptingWindows:
1000bec48:	bl	0x100eb1ee0 ; SELECTOR initWithDesktopIndependentWindow:
1000beedc:	bl	0x100eac480 ; SELECTOR captureImageWithFilter:configuration:completionHandler:
1000c0f88:	bl	0x100eb1fe0 ; SELECTOR initWithDisplay:includingApplications:exceptingWindows:
1000c12b4:	bl	0x100eb15c0 ; SELECTOR infoForFilter:
1000c12c8:	bl	0x100ead0a0 ; SELECTOR contentRect
1000c12f0:	bl	0x100eb60c0 ; SELECTOR pointPixelScale
1000c1430:	bl	0x100ebdae0 ; SELECTOR setWidth:
1000c149c:	bl	0x100ebae20 ; SELECTOR setHeight:
1000c14a8:	bl	0x100ebcac0 ; SELECTOR setShowsCursor:
1000c1700:	bl	0x100eac480 ; SELECTOR captureImageWithFilter:configuration:completionHandler:
1000c2850:	bl	0x100ebf3a0 ; SELECTOR systemRedColor
1000c28bc:	bl	0x100ea76d4 ; symbol stub for: _CGContextStrokeRect
1000c290c:	bl	0x100ebf3a0 ; SELECTOR systemRedColor
1000c294c:	bl	0x100ebf3a0 ; SELECTOR systemRedColor
1000c2c18:	bl	0x100ea77b8 ; symbol stub for: _CGImageDestinationCreateWithData
1000c2dc0:	bl	0x100ea77ac ; symbol stub for: _CGImageDestinationAddImage
1000c2dd0:	bl	0x100ea77c4 ; symbol stub for: _CGImageDestinationFinalize
10019e008:	add	x8, x8, #0x0 ; literal pool for: "AXVisibleCharacterRange"
10019e348:	add	x8, x8, #0xfe0 ; literal pool for: "AXStringForRange"
1001ac320:	add	x8, x8, #0xfe0 ; literal pool for: "AXStringForRange"
1001af8b4:	adrp	x8, 3586 ; 0x100fb1000
1001af8b8:	add	x8, x8, #0xf80 ; literal pool for: "AXEnhancedUserInterface"
1001af8bc:	sub	x8, x8, #0x20
1001af8c0:	orr	x0, x22, #0x2
1001af8c4:	orr	x1, x8, #0x8000000000000000
1001af8c8:	bl	0x100ea51e4 ; symbol stub for: _$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF
1001af8cc:	mov	x22, x0
1001af8d0:	mov	w0, #0x1
1001af8d4:	bl	0x100ea573c ; symbol stub for: _$sSb10FoundationE19_bridgeToObjectiveCSo8NSNumberCyF
1001af8d8:	mov	x23, x0
1001af8dc:	mov	x0, x21
1001af8e0:	mov	x1, x22
1001af8e4:	mov	x2, x23
1001af8e8:	bl	0x100ea7080 ; symbol stub for: _AXUIElementSetAttributeValue
1001af8ec:	mov	x24, x0
1001af8f0:	mov	x0, x22
1001af8f4:	bl	0x100ea8a90 ; symbol stub for: _objc_release
1001af8f8:	mov	x0, x23
1001af8fc:	bl	0x100ea8a90 ; symbol stub for: _objc_release
1001af900:	adrp	x8, 3586 ; 0x100fb1000
1001af904:	add	x8, x8, #0xf60 ; literal pool for: "AXManualAccessibility"
1001af908:	sub	x25, x8, #0x20
1001af90c:	orr	x1, x25, #0x8000000000000000
1001af910:	mov	x0, #0x15
1001af914:	movk	x0, #0xd000, lsl #48
1001af918:	bl	0x100ea51e4 ; symbol stub for: _$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF
1001af91c:	mov	x22, x0
1001af920:	mov	w0, #0x1
1001af924:	bl	0x100ea573c ; symbol stub for: _$sSb10FoundationE19_bridgeToObjectiveCSo8NSNumberCyF
1001af928:	mov	x23, x0
1001af92c:	mov	x0, x21
1001af930:	mov	x1, x22
1001af934:	mov	x2, x23
1001af938:	bl	0x100ea7080 ; symbol stub for: _AXUIElementSetAttributeValue
```

## Bounded runtime observation

**Directly observed — initial runtime baseline; no confirmed Scribe trial in this interval.** This initial metadata observer stopped afterward. A separate later manual-test session is documented in [live results](live-results.md).

From `2026-09-27T01:49:39.635596+00:00` to `2026-09-27T02:01:23.408896+00:00`: 100 snapshots. Only the main Willow process was present in bundle-specific process samples. No socket endpoints appeared in the periodic lsof samples. The inspected async.log stayed at zero bytes. Cache metadata changed. Independent nettop snapshots fluctuated; do not sum them or label a difference as a Scribe upload.

[Machine-readable summary](runtime-summary.json). No content from the HTTP cache was read. No generated output, screenshot upload, or successful app-specific context recovery is claimed.
