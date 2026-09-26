import Foundation
import XCTest
@testable import DesktopRewriteKit

final class ReplyContextContractTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: tests.appendingPathComponent("Fixtures/ReplyContext/\(name).json"))
    }

    func testSharedContextFixturesRoundTripWithoutLosingUnknowns() throws {
        for name in ["direct-ja", "group-en", "quoted-zh", "ambiguous", "context-regions-v2"] {
            let data = try fixture(name)
            let context = try JSONDecoder().decode(ReplyContext.self, from: data)
            let encoded = try JSONEncoder().encode(context)
            let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
            let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
            XCTAssertEqual(actual, expected)
        }
        let quoted = try JSONDecoder().decode(ReplyContext.self, from: fixture("quoted-zh"))
        XCTAssertNil(quoted.messages[1].participantId)
        XCTAssertEqual(quoted.messages[1].quotedByMessageId, "m1")
        let group = try JSONDecoder().decode(ReplyContext.self, from: fixture("group-en"))
        XCTAssertEqual(group.participants.count, 2)
        XCTAssertEqual(group.selectedTargetText, "Alex (Design): Can you review the mockups?")
    }

    func testCapturePreservesMultipleConversationsAndTruncation() throws {
        let evidence = try JSONDecoder().decode(CapturedReplyEvidence.self, from: fixture("captured-two-threads"))
        XCTAssertEqual(evidence.status, .partial)
        XCTAssertEqual(Set(evidence.blocks.map(\.conversationId)).count, 2)
        XCTAssertEqual(evidence.truncationReasons, ["node_budget"])
    }

    func testRegionEvidenceRoundTripsAndBindsContextAcrossNestedContainers() throws {
        let data = try fixture("captured-regions-v2")
        let evidence = try JSONDecoder().decode(CapturedReplyEvidence.self, from: data)
        XCTAssertEqual(evidence.version, 2)
        let encoded = try JSONEncoder().encode(evidence)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let context = try JSONDecoder().decode(ReplyContext.self, from: fixture("context-regions-v2"))
        XCTAssertTrue(context.isBound(to: evidence))
        XCTAssertEqual(context.selectedTargetText, "明日の15時は空いていますか？")
    }

    func testStructuredReplyRequestIsAdditiveAndKeepsBillingIdentity() throws {
        let context = try JSONDecoder().decode(ReplyContext.self, from: fixture("direct-ja"))
        let request = RewriteRequest(
            prompt: "", text: "", appVersion: "test", captureMode: .wholeInput,
            requestId: "same-intent", replyContext: context, draftReadStatus: .unreadable
        )
        let data = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(body["replyTo"])
        XCTAssertEqual(body["draftReadStatus"] as? String, "unreadable")
        XCTAssertEqual(body["requestId"] as? String, "same-intent")
        XCTAssertEqual(body["candidateCount"] as? Int, 3)
        XCTAssertEqual(try JSONDecoder().decode(RewriteRequest.self, from: data).replyContext, context)

        let legacy = RewriteRequest(prompt: "yes", text: "", replyTo: "明日？", appVersion: "test", captureMode: .wholeInput)
        let legacyBody = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(legacyBody["replyContext"])
        XCTAssertNil(legacyBody["draftReadStatus"])
        XCTAssertEqual(legacyBody["replyTo"] as? String, "明日？")
    }
}

extension ReplyContextContractTests {
    func testV3CaptureRoundTripsAndBindsExistingV2WriterContext() throws {
        let data = try fixture("captured-observations-v3")
        let evidence = try JSONDecoder().decode(CapturedReplyEvidence.self, from: data)
        XCTAssertEqual(evidence.version, 3)
        XCTAssertEqual(evidence.observations?.filter { $0.kind == "composer" }.count, 1)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: JSONEncoder().encode(evidence)) as? NSDictionary)
        let context = try JSONDecoder().decode(ReplyContext.self, from: fixture("context-regions-v2"))
        XCTAssertTrue(context.isBound(to: evidence))
    }
}
