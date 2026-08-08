import XCTest
@testable import DesktopRewriteKit

/// These guard the contract with the iOS repo (§3). If one of these fails, the two
/// surfaces have drifted and it is a two-repo change, not a local fix.
final class ContractTests: XCTestCase {

    // MARK: - UserPrompt

    /// A real PostgREST row shape, snake_case, with `origin` present.
    func testDecodesPostgrestRow() throws {
        let json = """
        {
          "id": "6C7A2B5E-7B1F-4E2A-9C3D-1A2B3C4D5E6F",
          "slot": "sub",
          "builtinKey": "polite",
          "origin": "onboarding_builder",
          "title": "敬語",
          "prompt": "丁寧に書き直してください。",
          "isEnabled": true,
          "sortOrder": 2,
          "createdAt": "2026-07-01T09:00:00Z",
          "updatedAt": "2026-07-02T09:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let prompt = try decoder.decode(UserPrompt.self, from: Data(json.utf8))

        XCTAssertEqual(prompt.title, "敬語")
        XCTAssertEqual(prompt.slot, .sub)
        XCTAssertEqual(prompt.origin, .onboardingBuilder)
        XCTAssertEqual(prompt.sortOrder, 2)
    }

    /// Rows predating the `origin` column must not fail to decode — §3's whole point
    /// is that this type reads what the iOS app already wrote.
    func testInfersOriginWhenColumnAbsent() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let builtin = try decoder.decode(UserPrompt.self, from: Data("""
        {"id":"6C7A2B5E-7B1F-4E2A-9C3D-1A2B3C4D5E6F","slot":"main","builtinKey":"polite",
         "title":"敬語","prompt":"p","isEnabled":true,"sortOrder":0,
         "createdAt":"2026-07-01T09:00:00Z","updatedAt":"2026-07-01T09:00:00Z"}
        """.utf8))
        XCTAssertEqual(builtin.origin, .builtin)

        let authored = try decoder.decode(UserPrompt.self, from: Data("""
        {"id":"7C7A2B5E-7B1F-4E2A-9C3D-1A2B3C4D5E6F","slot":"sub",
         "title":"自作","prompt":"p","isEnabled":true,"sortOrder":1,
         "createdAt":"2026-07-01T09:00:00Z","updatedAt":"2026-07-01T09:00:00Z"}
        """.utf8))
        XCTAssertEqual(authored.origin, .userAuthored)
    }

    // MARK: - Hover row ordering (§4)

    /// `main` leads, then `sub` by `sortOrder`. Disabled buttons are dropped.
    ///
    /// The `main` button must not be hidden just because it lives in a different slot
    /// — on iOS that slot is a separate toolbar position, but a single row has no such
    /// split, and dropping it would remove the user's most-used button.
    func testHoverRowFlattensBothSlots() {
        let prompts = [
            make(title: "英訳", slot: .sub, sortOrder: 2),
            make(title: "無効", slot: .sub, sortOrder: 0, enabled: false),
            make(title: "敬語", slot: .main, sortOrder: 0),
            make(title: "要約", slot: .sub, sortOrder: 1),
        ]

        XCTAssertEqual(
            prompts.enabledForHoverRow.map(\.title),
            ["敬語", "要約", "英訳"]
        )
    }

    /// §4 claims no overflow handling is needed because the live p99 is 5 buttons and
    /// the max is 7. This pins the assumption the layout depends on.
    func testHoverRowWorstCaseIsEightPills() {
        let prompts = (0..<7).map { make(title: "ボタン\($0)", slot: .sub, sortOrder: $0) }
        XCTAssertEqual(prompts.enabledForHoverRow.count + 1, 8, "7 buttons plus ✎")
    }

    // MARK: - RewriteRequest superset (§6)

    /// The four macOS fields must be present and `surface` must be pinned, otherwise
    /// `desktop.rewrite_events` cannot be separated from the keyboard's log.
    func testEncodesMacOSSuperset() throws {
        let request = RewriteRequest(
            prompt: "丁寧に",
            text: "了解",
            appVersion: "0.1.0",
            selection: true,
            selectionContextBefore: "前",
            selectionContextAfter: "後",
            hostAppBundleId: "com.apple.mail",
            captureMode: .selection,
            browserURL: nil,
            ioPath: "ax"
        )

        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertEqual(json?["surface"] as? String, "macos")
        XCTAssertEqual(json?["captureMode"] as? String, "selection")
        XCTAssertEqual(json?["hostAppBundleId"] as? String, "com.apple.mail")
        XCTAssertEqual(json?["candidateCount"] as? Int, 3, "the shared model's default stays 3 (§3)")
        // browserURL is nil here; the key may be absent, but it must never be wrong.
        XCTAssertNil(json?["browserURL"] as? String)
    }

    /// `io_path` is §7's earliest warning that an app's AX tree changed. Only the
    /// client knows which path it took, so if this stops going over the wire the
    /// column goes permanently null and the signal is silently lost.
    func testSendsIOPathSoTheColumnIsNotAlwaysNull() throws {
        for path in ["ax", "clipboard"] {
            let request = RewriteRequest(
                prompt: "p",
                text: "t",
                appVersion: "0.1.0",
                captureMode: .wholeInput,
                ioPath: path
            )
            let json = try JSONSerialization.jsonObject(
                with: try JSONEncoder().encode(request)
            ) as? [String: Any]
            XCTAssertEqual(json?["ioPath"] as? String, path)
        }
    }

    /// The desktop asks for one candidate, and the override has to survive encoding.
    /// `parseRequest` falls back to `DEFAULT_CANDIDATES` (3) whenever the key is
    /// absent, so a dropped field does not fail — it silently restores the phone's
    /// count, and `reserveUsage` bills units by candidate. The symptom would be a
    /// usage bill, not a bug report.
    func testSendsExplicitCandidateCount() throws {
        let request = RewriteRequest(
            prompt: "p",
            text: "t",
            appVersion: "0.1.0",
            candidateCount: 1,
            captureMode: .wholeInput,
            ioPath: "ax"
        )

        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertEqual(json?["candidateCount"] as? Int, 1)
    }

    /// `replyTo` is what selects the backend's reply branch — `systemInstructions`
    /// switches on `!!request.replyTo?.trim()` and nothing else does. If the key stops
    /// going over the wire, reply mode does not fail: it silently degrades into
    /// rewriting the user's draft, which for the usual empty compose box is a rewrite
    /// of an empty string.
    func testSendsReplyToSoTheBackendTakesTheReplyBranch() throws {
        let request = RewriteRequest(
            prompt: "丁寧に断ってください",
            // Reply mode's `text` is the user's own draft, and it is *usually empty* —
            // `parseRequest` requires the key to be present but permits "".
            text: "",
            replyTo: "来週の懇親会にご参加いただけますか。",
            appVersion: "0.1.0",
            captureMode: .wholeInput,
            ioPath: "ax"
        )

        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertEqual(json?["replyTo"] as? String, "来週の懇親会にご参加いただけますか。")
        XCTAssertEqual(json?["text"] as? String, "")
        XCTAssertEqual(json?["prompt"] as? String, "丁寧に断ってください")
    }

    /// The default has to stay nil, or every rewrite would take the reply branch.
    func testOmitsReplyToOutsideReplyMode() throws {
        let request = RewriteRequest(
            prompt: "丁寧に",
            text: "了解",
            appVersion: "0.1.0",
            captureMode: .wholeInput
        )
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(request)
        ) as? [String: Any]
        XCTAssertNil(json?["replyTo"] as? String)
    }

    /// The response shape is unchanged from the keyboard's: `{candidates, language, eventId}`.
    func testDecodesUnchangedResponseShape() throws {
        let json = """
        {"candidates":[{"replacement":"承知しました","changed":true}],
         "language":"ja","eventId":"abc-123"}
        """
        let result = try JSONDecoder().decode(RewriteResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertEqual(result.candidates[0].replacement, "承知しました")
        XCTAssertEqual(result.eventId, "abc-123")
    }

    /// The backend does not send candidate ids; one has to be synthesized or
    /// `ForEach` in the pager has nothing stable to key on.
    func testCandidateGetsIdWhenServerOmitsIt() throws {
        let result = try JSONDecoder().decode(
            RewriteResult.self,
            from: Data(#"{"candidates":[{"replacement":"a"}],"language":"ja"}"#.utf8)
        )
        XCTAssertEqual(result.candidates.count, 1)
        XCTAssertTrue(result.candidates[0].changed, "defaults to changed")
    }

    // MARK: - JWT

    func testExtractsSubjectFromJWT() {
        // {"alg":"HS256"}.{"sub":"user-42","exp":9999999999}.sig — unpadded base64url,
        // which is what Supabase actually returns.
        let token = "eyJhbGciOiJIUzI1NiJ9"
            + ".eyJzdWIiOiJ1c2VyLTQyIiwiZXhwIjo5OTk5OTk5OTk5fQ"
            + ".signature"
        XCTAssertEqual(AuthService.userId(fromJWT: token), "user-42")
    }

    func testRejectsMalformedJWT() {
        XCTAssertNil(AuthService.userId(fromJWT: "not-a-token"))
        XCTAssertNil(AuthService.userId(fromJWT: ""))
    }

    // MARK: - Helpers

    private func make(
        title: String,
        slot: UserPrompt.Slot,
        sortOrder: Int,
        enabled: Bool = true
    ) -> UserPrompt {
        UserPrompt(
            slot: slot,
            title: title,
            prompt: "p",
            isEnabled: enabled,
            sortOrder: sortOrder
        )
    }
}
