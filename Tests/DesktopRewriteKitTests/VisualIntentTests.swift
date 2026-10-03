import XCTest
@testable import DesktopRewriteKit

final class VisualIntentTests: XCTestCase {
    func testCapturedChromeChildWindowUnionIsRejected() {
        let window = CGRect(x: 0, y: 122, width: 1920, height: 958)
        let composer = CGRect(x: 991, y: 786, width: 888, height: 111)
        XCTAssertNil(VisualCaptureGeometry.frameImageBox(composer: composer, window: window, screenRect: window,
            contentRect: CGRect(x: 0, y: 0, width: 1703.111114501953, height: 958.0000019073486),
            contentScale: 0.8870370388031006, scaleFactor: 1, width: 1920, height: 958))
        XCTAssertEqual(VisualCaptureGeometry.frameImageBox(composer: composer, window: window, screenRect: window,
            contentRect: CGRect(x: 0, y: 0, width: 1920, height: 958), contentScale: 1, scaleFactor: 1,
            width: 1920, height: 958)?.rect, CGRect(x: 991, y: 664, width: 888, height: 111))
    }

    func testFrameMappingUsesContentPlacementRetinaAndNegativeDisplayOrigin() {
        let window = CGRect(x: -1600, y: -900, width: 1000, height: 800)
        let box = VisualCaptureGeometry.frameImageBox(composer: CGRect(x: -1400, y: -400, width: 400, height: 100),
            window: window, screenRect: window, contentRect: CGRect(x: 10, y: 20, width: 500, height: 400),
            contentScale: 0.5, scaleFactor: 2, width: 1200, height: 900)
        XCTAssertEqual(box?.rect, CGRect(x: 220, y: 540, width: 400, height: 100))
        XCTAssertNil(VisualCaptureGeometry.frameImageBox(composer: CGRect(x: -1400, y: -400, width: 400, height: 100),
            window: window, screenRect: window.offsetBy(dx: 30, dy: 0),
            contentRect: CGRect(x: 10, y: 20, width: 500, height: 400), contentScale: 0.5, scaleFactor: 2,
            width: 1200, height: 900))
    }

    func testFrameMappingRejectsInvalidOrClippedMetadata() {
        let window = CGRect(x: 0, y: 0, width: 100, height: 100)
        for scale in [Double.nan, 0, -1] {
            XCTAssertNil(VisualCaptureGeometry.frameImageBox(composer: window, window: window, screenRect: window,
                contentRect: window, contentScale: scale, scaleFactor: 1, width: 100, height: 100))
        }
        XCTAssertNil(VisualCaptureGeometry.frameImageBox(composer: window, window: window, screenRect: window,
            contentRect: window.offsetBy(dx: 20, dy: 0), contentScale: 1, scaleFactor: 1, width: 100, height: 100))
    }
    func testRetinaMappingOnDisplayLeftOfMain() {
        let box = VisualCaptureGeometry.imageBox(composer: CGRect(x: -1400, y: 600, width: 400, height: 100),
            window: CGRect(x: -1600, y: 100, width: 1000, height: 800), width: 2000, height: 1600)
        XCTAssertEqual(box?.rect, CGRect(x: 400, y: 1000, width: 800, height: 200))
    }

    func testMappingUsesActualPixelsAndTopLeftOriginOnDisplayAboveMain() {
        let box = VisualCaptureGeometry.imageBox(composer: CGRect(x: 110, y: -700, width: 80, height: 50),
            window: CGRect(x: 10, y: -900, width: 800, height: 600), width: 1200, height: 900)
        XCTAssertEqual(box?.rect, CGRect(x: 150, y: 300, width: 120, height: 75))
    }

    func testClippedComposerAndInvalidGeometryFail() {
        XCTAssertNil(VisualCaptureGeometry.imageBox(composer: CGRect(x: -1, y: 10, width: 20, height: 10),
            window: CGRect(x: 0, y: 0, width: 100, height: 100), width: 200, height: 200))
        XCTAssertFalse(ImageBox(CGRect(x: 0, y: 0, width: 0, height: 1)).fits(width: 100, height: 100))
        XCTAssertFalse(VisualCaptureGeometry.agrees(CGRect(x: 0, y: 0, width: 10, height: 10),
            CGRect(x: 5, y: 0, width: 10, height: 10)))
    }

    private var request: VisualIntentRequest {
        VisualIntentRequest(captureId: "c", targetId: "right", intent: "agree and mention the amount",
            appBundleId: "test", imageWidth: 1000, imageHeight: 800,
            composerBox: ImageBox(CGRect(x: 600, y: 700, width: 300, height: 80)), imageBase64: "")
    }

    private func result(_ changes: [String: Any] = [:]) throws -> VisualIntentResult {
        let box: [String: Any] = ["x": 600, "y": 100, "width": 300, "height": 200]
        var value: [String: Any] = ["captureId": "c", "targetId": "right", "status": "ready",
            "conversationRegion": [["label": "right thread", "box": box]],
            "evidence": [["excerpt": "Budget: 7500", "box": box, "author": NSNull(), "partial": false]],
            "missingContext": [], "draft": "I agree about the 7500 budget."]
        value.merge(changes) { _, new in new }
        return try JSONDecoder().decode(VisualIntentResult.self, from: JSONSerialization.data(withJSONObject: value))
    }

    func testCorrelationAndGroundingAreRequired() throws {
        XCTAssertNoThrow(try result().validate(for: request))
        XCTAssertThrowsError(try result(["targetId": "left"]).validate(for: request))
        XCTAssertThrowsError(try result(["captureId": "old"]).validate(for: request))
        XCTAssertThrowsError(try result(["evidence": []]).validate(for: request))
        XCTAssertThrowsError(try result(["draft": "   "]).validate(for: request))
        XCTAssertThrowsError(try result(["missingContext": ["opening unavailable"]]).validate(for: request))
    }

    func testAbstentionCannotCarryDraft() throws {
        XCTAssertThrowsError(try result(["status": "insufficient_context"]).validate(for: request))
        XCTAssertNoThrow(try result(["status": "insufficient_context", "draft": NSNull(),
            "missingContext": ["Opening is clipped"]]).validate(for: request))
    }

    func testReasoningMetadataSurvivesExportAndOlderResponsesStillDecode() throws {
        let encoder = JSONEncoder()
        var value: [String: Any] = ["result": try JSONSerialization.jsonObject(with: encoder.encode(result())),
            "model": "gpt-6-luna", "promptVersion": "visual-intent-a-3", "modelMs": 100,
            "inputTokens": 100, "outputTokens": 50, "reasoningEffort": "low"]
        let response = try JSONDecoder().decode(VisualIntentResponse.self, from: JSONSerialization.data(withJSONObject: value))
        XCTAssertEqual(response.reasoningEffort, "low")
        let exported = try JSONSerialization.jsonObject(with: encoder.encode(response)) as! [String: Any]
        XCTAssertEqual(exported["reasoningEffort"] as? String, "low")
        value.removeValue(forKey: "reasoningEffort")
        let old = try JSONDecoder().decode(VisualIntentResponse.self, from: JSONSerialization.data(withJSONObject: value))
        XCTAssertNil(old.reasoningEffort)
    }

    func testEvidenceOverlapDoesNotDiscardDraftForEvaluation() throws {
        let evidence: [[String: Any]] = [["excerpt": request.intent, "box": ["x": 600, "y": 700, "width": 300, "height": 80],
                                          "author": NSNull(), "partial": false]]
        XCTAssertNoThrow(try result(["evidence": evidence]).validate(for: request))
        let slight: [[String: Any]] = [["excerpt": "Budget: 7500", "box": ["x": 600, "y": 680, "width": 300, "height": 21],
                                       "author": NSNull(), "partial": false]]
        XCTAssertNoThrow(try result(["evidence": slight]).validate(for: request))
    }

    func testImportedCaptureCannotEscapeExportDirectory() throws {
        let safe = VisualIntentRequest(captureId: "capture-1", targetId: "right", intent: "agree", appBundleId: "test",
            imageWidth: 1000, imageHeight: 800, composerBox: request.composerBox, imageBase64: "/9j/AAAA")
        XCTAssertNoThrow(try safe.validate())
        let unsafe = VisualIntentRequest(captureId: "../../escape", targetId: "right", intent: "agree", appBundleId: "test",
            imageWidth: 1000, imageHeight: 800, composerBox: request.composerBox, imageBase64: "/9j/AAAA")
        XCTAssertThrowsError(try unsafe.validate())
        XCTAssertFalse(ImageBox(CGRect(x: 0, y: 0, width: 10, height: 10))
            .overlaps(ImageBox(CGRect(x: 0, y: 10, width: 10, height: 10))))
    }
}
