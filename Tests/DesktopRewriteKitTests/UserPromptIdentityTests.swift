import XCTest
@testable import DesktopRewriteKit

/// `user_prompts_user_builtin_unique` is a second unique key the Swift model cannot see,
/// so every case here is really about one question: does the write still reach the row the
/// account already owns for that `builtin_key`?
final class UserPromptIdentityTests: XCTestCase {

    /// The 409. A preset pack mints fresh ids, the phone already seeded `polite`, and
    /// `on_conflict=id` cannot resolve a conflict on a different key.
    func testPresetAdoptsTheRowTheAccountAlreadyOwnsForThatBuiltinKey() {
        let seeded = make("敬語", builtinKey: "polite", origin: .builtin)
        let fromPack = make("敬語", builtinKey: "polite", origin: .onboardingPreset)

        let reconciled = UserPromptIdentity.reconciled([fromPack], existing: [seeded])

        XCTAssertEqual(reconciled.map(\.id), [seeded.id])
        XCTAssertNotEqual(fromPack.id, seeded.id)
    }

    /// Only the text is being replaced, so the row keeps the day the phone made it.
    func testAdoptedRowKeepsItsOriginalCreationDate() {
        let seeded = make(
            "敬語",
            builtinKey: "polite",
            origin: .builtin,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let fromPack = make("敬語", builtinKey: "polite", origin: .onboardingPreset)

        let reconciled = UserPromptIdentity.reconciled([fromPack], existing: [seeded])

        XCTAssertEqual(reconciled.first?.createdAt, seeded.createdAt)
        XCTAssertEqual(reconciled.first?.origin, .onboardingPreset)
        XCTAssertEqual(reconciled.first?.title, fromPack.title)
    }

    /// `work` and `social` carry no builtin keys — the packs that already worked.
    func testButtonsWithoutABuiltinKeyKeepTheirOwnIdentity() {
        let seeded = make("敬語", builtinKey: "polite", origin: .builtin)
        let authored = make("社内チャット", builtinKey: nil, origin: .onboardingPreset)

        let reconciled = UserPromptIdentity.reconciled([authored], existing: [seeded])

        XCTAssertEqual(reconciled.map(\.id), [authored.id])
        XCTAssertNil(reconciled.first?.builtinKey)
    }

    func testAKeyTheAccountDoesNotOwnKeepsTheNewIdentity() {
        let seeded = make("敬語", builtinKey: "polite", origin: .builtin)
        let english = make("英訳", builtinKey: "translateToEnglish", origin: .onboardingPreset)

        let reconciled = UserPromptIdentity.reconciled([english], existing: [seeded])

        XCTAssertEqual(reconciled.map(\.id), [english.id])
        XCTAssertEqual(reconciled.first?.builtinKey, "translateToEnglish")
    }

    /// 「現在のボタンを使う」 already sends the owned ids; reconciling must not move them.
    func testExistingButtonsPassThroughUnchanged() {
        let seeded = [
            make("敬語", builtinKey: "polite", origin: .builtin),
            make("メール", builtinKey: "email", origin: .builtin),
            make("自作", builtinKey: nil, origin: .userAuthored),
        ]

        let reconciled = UserPromptIdentity.reconciled(seeded, existing: seeded)

        XCTAssertEqual(reconciled, seeded)
    }

    /// Postgres refuses to let ON CONFLICT DO UPDATE touch one row twice, so two claims on
    /// one key must not both resolve to the owner's id — and neither button is dropped.
    func testTwoClaimsOnOneKeyDoNotProduceADuplicateId() {
        let seeded = make("敬語", builtinKey: "polite", origin: .builtin)
        let first = make("敬語", builtinKey: "polite", origin: .onboardingPreset)
        let second = make("ていねいに", builtinKey: "polite", origin: .onboardingPreset)

        let reconciled = UserPromptIdentity.reconciled([first, second], existing: [seeded])

        XCTAssertEqual(reconciled.count, 2)
        XCTAssertEqual(Set(reconciled.map(\.id)).count, 2)
        XCTAssertEqual(reconciled.first?.id, seeded.id)
        XCTAssertEqual(reconciled.last?.id, second.id)
        XCTAssertNil(reconciled.last?.builtinKey)
    }

    private func make(
        _ title: String,
        builtinKey: String?,
        origin: PromptOrigin,
        createdAt: Date = Date(timeIntervalSince1970: 2_000)
    ) -> UserPrompt {
        UserPrompt(
            id: UUID(),
            slot: .sub,
            builtinKey: builtinKey,
            title: title,
            prompt: "p",
            origin: origin,
            createdAt: createdAt,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }
}
