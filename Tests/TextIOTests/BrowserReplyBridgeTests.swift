import XCTest
import Foundation
import Darwin
@testable import TextIO

final class BrowserReplyBridgeTests: XCTestCase {
    func testFramingHandlesUnicodeAndRejectsOversizedPayload() throws {
        let pipe = Pipe(), text = Data("日本語\nreply".utf8)
        try ReplyBridgeWire.writeFrame(text, to: pipe.fileHandleForWriting.fileDescriptor)
        XCTAssertEqual(try ReplyBridgeWire.readFrame(pipe.fileHandleForReading.fileDescriptor), text)
        XCTAssertThrowsError(try ReplyBridgeWire.frame(Data(count: ReplyBridgeWire.limit + 1)))
    }
    func testSourceFailuresCannotSilentlyBecomeAXFallbacks() {
        for reason in ["ambiguous_target", "target_changed", "current_message_budget", "missing_current_history", "conversation_unresolved", "invalid_dom_capture"] {
            XCTAssertFalse(ReplyCaptureCoordinator.permitsAXFallback(reason))
        }
        for reason in ["extension_unavailable", "permission_missing", "unsupported_surface", "transport_unavailable"] {
            XCTAssertTrue(ReplyCaptureCoordinator.permitsAXFallback(reason))
        }
    }
    func testRealNativeHostRelaysCaptureAndVerificationOverPrivateSocket() async throws {
        let directory = URL(fileURLWithPath: "/tmp/reply-bridge-\(UUID().uuidString)")
        setenv("KEIGO_REPLY_BRIDGE_DIR", directory.path, 1)
        let bridge = BrowserReplyBridge()
        XCTAssertNil(bridge.startupFailure)
        defer { bridge.stop(); unsetenv("KEIGO_REPLY_BRIDGE_DIR"); try? FileManager.default.removeItem(at: directory) }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = root.appendingPathComponent(".build/debug/ReplyNativeHost")
        process.arguments = [ReplyBridgeIdentity.origin]
        var environment = ProcessInfo.processInfo.environment
        environment["KEIGO_REPLY_BRIDGE_DIR"] = directory.path
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = Pipe()
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let served = expectation(description: "two Chrome protocol responses")
        DispatchQueue.global().async {
            do {
                for _ in 0..<2 {
                    let data = try ReplyBridgeWire.readFrame(output.fileHandleForReading.fileDescriptor, deadline: Date().addingTimeInterval(5))
                    let request = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                    var response: [String: Any] = ["protocol": 1, "id": request["id"]!, "status": "ok"]
                    if request["operation"] as? String == "capture" {
                        response["binding"] = ["documentToken":"doc", "conversationId":"c1", "composerId":"editor", "tabId":1, "windowId":2, "documentId":"document", "frameId":0]
                        response["evidence"] = ["version":4,"snapshotId":"snapshot","blocks":[["id":"b0","conversationId":"c1","text":"Message","order":0]],"status":"partial","truncationReasons":["loaded_history_only"],"regions":[["id":"c1","role":"conversation","containsFocus":true]],"dom":["source":"dom","adapter":"gmail","revision":"dom-1","conversationId":"c1","composerId":"editor","headerBlockIds":[],"coverage":["loaded_history_only"],"messages":[["id":"m0","bodyBlockIds":["b0"],"quoteBlockIds":[],"order":0,"visibility":"loaded","coverage":"complete"]]]]
                    } else { response["result"] = "verified" }
                    try ReplyBridgeWire.writeFrame(JSONSerialization.data(withJSONObject: response), to: input.fileHandleForWriting.fileDescriptor)
                }
            } catch { XCTFail("native relay failed: \(error)") }
            served.fulfill()
        }
        // Allow the child to register; only extension absence is retryable here.
        var capture: BrowserReplyResponse?
        for _ in 0..<30 {
            do { capture = try await bridge.capture(snapshotId: "snapshot", browserPID: getpid()); break }
            catch { if (error as? BrowserReplyError)?.reason != "extension_unavailable" { throw error } }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(bridge.connectedBrowserPIDs.contains(getpid()))
        let binding = try XCTUnwrap(capture?.binding)
        XCTAssertEqual(capture?.evidence?.blocks.first?.text, "Message")
        let result = try await bridge.validate(binding, expectedText: "Generated reply")
        XCTAssertEqual(result, "verified")
        await fulfillment(of: [served], timeout: 5)
    }
}
