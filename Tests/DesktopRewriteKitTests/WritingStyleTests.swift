import Foundation
import XCTest
@testable import DesktopRewriteKit

final class WritingStyleTests: XCTestCase {
    func testAllDefaultsAreMiddleAndInvalidChoicesCannotCrossContexts() throws {
        for context in WritingContext.allCases {
            var profile = WritingStyleProfile(context: context)
            XCTAssertEqual(profile.voice, context.voiceOptions[1])
            XCTAssertEqual(profile.detail, context.detailOptions[1])
            profile.chooseDetail("invalid")
            XCTAssertEqual(profile.detail, context.defaultDetail)
        }
    }
    func testAll36CombinationsRoundTripSharedWireFixture() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/writing-styles-v1.json"))
        let snapshots = try JSONDecoder().decode([ResolvedWritingStyle].self, from: data)
        XCTAssertEqual(snapshots.count, 36)
        for snapshot in snapshots {
            let data = try JSONEncoder().encode(snapshot)
            XCTAssertEqual(try JSONDecoder().decode(ResolvedWritingStyle.self, from: data), snapshot)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object[snapshot.profile.context.detailKey] as? String, snapshot.profile.detail)
            XCTAssertNil(object["profile"])
        }
    }
    func testWorkDetailMigrationKeepsNotesVoiceAndMappingsAndUsesNormalDefault() throws {
        for (old, expected) in [("preserve", "balanced"), ("streamline", "balanced"), ("structure", "detailed")] {
            let data = Data("""
            {"version":1,"profiles":[{"context":"work_chat","voice":"casual","detail":"\(old)","notes":"Keep product names"}],"mappings":{"app:example":"work_chat"}}
            """.utf8)
            let document = try JSONDecoder().decode(WritingStyleDocument.self, from: data)
            let profile = document.profile(for: .workChat)
            XCTAssertEqual(profile.detail, expected)
            XCTAssertEqual(profile.voice, "casual")
            XCTAssertEqual(profile.notes, "Keep product names")
            XCTAssertEqual(document.mappings["app:example"], .workChat)
            XCTAssertEqual(try JSONDecoder().decode(WritingStyleDocument.self, from: JSONEncoder().encode(document)), document)
        }
        let partial = try JSONDecoder().decode(WritingStyleProfile.self, from: Data(#"{"context":"work_chat"}"#.utf8))
        XCTAssertEqual(partial.detail, "balanced")
        XCTAssertEqual(WritingContext.workChat.detailOptions, ["concise", "balanced", "detailed"])
    }
    @MainActor
    func testAccountIsolationPersistencePartialDefaultsAndStaleWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WritingStyleStore(directory: directory)
        store.activate(accountID: "A")
        var document = store.document
        var email = document.profile(for: .email)
        email.chooseVoice("formal"); email.notes = "Keep terms"
        document.set(email)
        XCTAssertTrue(store.save(document, for: "A"))
        let oldRevision = store.activationRevision
        store.activate(accountID: "B")
        XCTAssertFalse(store.activate(accountID: "A", expectedRevision: oldRevision))
        XCTAssertEqual(store.document.profile(for: .email).voice, "polite")
        XCTAssertFalse(store.save(document, for: "A"))
        let relaunched = WritingStyleStore(directory: directory)
        relaunched.activate(accountID: "A")
        XCTAssertEqual(relaunched.document.profile(for: .email), email)
        let partial = try JSONDecoder().decode(WritingStyleDocument.self, from: Data(#"{"version":1,"profiles":[{"context":"email","voice":"formal"}]}"#.utf8))
        XCTAssertEqual(partial.profile(for: .email).voice, "formal")
        XCTAssertEqual(partial.profile(for: .email).detail, "readable")
        XCTAssertEqual(partial.profiles.count, 4)
        store.activate(accountID: nil)
        XCTAssertEqual(store.document.profile(for: .email).notes, "")
    }
    @MainActor
    func testFutureAndCorruptFilesAreNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("41.json")
        for contents in ["broken", #"{"version":99}"#] {
            try Data(contents.utf8).write(to: url)
            let store = WritingStyleStore(directory: directory)
            store.activate(accountID: "A")
            XCTAssertEqual(store.error, "load")
            XCTAssertFalse(store.save(WritingStyleDocument(), for: "A"))
            XCTAssertEqual(try String(contentsOf: url), contents)
        }
    }
    @MainActor
    func testExplicitRecoveryPreservesOriginalBeforeResetting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data(#"{"version":99}"#.utf8)
        try original.write(to: directory.appendingPathComponent("41.json"))
        let store = WritingStyleStore(directory: directory)
        store.activate(accountID: "A")
        XCTAssertTrue(store.recoverWithDefaults())
        XCTAssertNil(store.error)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let preserved = try XCTUnwrap(files.first { $0.lastPathComponent.contains("preserved-") })
        XCTAssertEqual(try Data(contentsOf: preserved), original)
        let reopened = WritingStyleStore(directory: directory)
        reopened.activate(accountID: "A")
        XCTAssertEqual(reopened.document.profile(for: .email).voice, "polite")
    }

    @MainActor
    func testWriteFailureKeepsDraftForRetry() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = WritingStyleStore(directory: file)
        store.activate(accountID: "A")
        var doc = store.document
        var profile = doc.profile(for: .other); profile.notes = "Draft"
        doc.set(profile)
        XCTAssertFalse(store.save(doc, for: "A"))
        XCTAssertEqual(store.document.profile(for: .other).notes, "Draft")
        XCTAssertEqual(store.error, "save")
    }
    func testSurfaceResolutionIsBoundedAndCorrectionsDoNotOverrideExclusions() {
        let resolve = WritingContextResolver.resolve
        XCTAssertEqual(resolve("com.google.Chrome", "https://mail.google.com/mail/u/0", nil, [:], false, .unknown).context, .email)
        XCTAssertEqual(resolve("com.google.Chrome", "https://mail.google.com.evil.test/", nil, [:], false, .unknown).context, .other)
        XCTAssertEqual(resolve("com.google.Chrome", "https://outlook.office.com/calendar", nil, [:], false, .unknown).context, .other)
        XCTAssertEqual(resolve("com.google.Chrome", nil, nil, [:], false, .unknown).context, .other)
        XCTAssertNil(WritingContextResolver.mappingKey(bundleID: "com.google.Chrome", browserURL: nil))
        XCTAssertEqual(resolve("com.tinyspeck.slackmacgap", nil, nil, [:], false, .chat).context, .workChat)
        XCTAssertEqual(resolve("com.tinyspeck.slackmacgap", nil, nil, [:], false, .unknown).context, .other)
        XCTAssertEqual(resolve("com.apple.mail", nil, .personal, [:], false, .unknown).source, .userOnce)
        XCTAssertEqual(resolve("com.apple.mail", nil, .personal, [:], false, .excluded).context, .other)
        XCTAssertEqual(resolve("com.apple.mail", nil, nil, ["app:com.apple.mail": .personal], false, .unknown).source, .userMapping)
    }
    func testUnfinishedOldStepsMigrateAndCompletedUsersStayComplete() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = OnboardingProgressStore(defaults: defaults)
        for step in [DesktopOnboardingStep.writingStyle] {
            store.save(step: step)
            XCTAssertEqual(store.savedStep, .purpose)
        }
        store.complete()
        XCTAssertTrue(store.isComplete)
    }

    func testBrowserMailBodyHintRecoversMissingURLButNotKnownNonMailSurfaces() {
        XCTAssertEqual(WritingContextResolver.resolve(bundleID: "com.google.Chrome", browserURL: nil, hint: .mail).context, .email)
        XCTAssertEqual(WritingContextResolver.resolve(bundleID: "com.google.Chrome", browserURL: nil, hint: .unknown).context, .other)
        XCTAssertEqual(WritingContextResolver.resolve(bundleID: "com.google.Chrome", browserURL: "https://outlook.office.com/calendar", hint: .mail).context, .other)
        XCTAssertEqual(WritingContextResolver.resolve(bundleID: "com.google.Chrome", browserURL: "https://mail.google.com/mail/u/0/#chat/space", hint: .chat).context, .other)
        XCTAssertEqual(WritingContextResolver.resolve(bundleID: "com.google.Chrome", browserURL: nil, hint: .excluded).context, .other)
    }
}
