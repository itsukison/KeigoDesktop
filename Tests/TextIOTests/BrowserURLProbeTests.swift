import XCTest
@testable import TextIO

final class BrowserURLProbeTests: XCTestCase {
    func testDeepWebmailAndBlankFrameUseNearestHTTPAncestor() {
        let result = BrowserURLProbe.resolve(from: 0, sameNode: ==, read: { depth in
            .init(url: depth == 4 ? "about:blank" : depth == 25 ? "https://mail.google.com/mail/u/0/" : nil,
                  parent: depth + 1)
        }, documentURL: { XCTFail("Ancestor URL should win"); return nil }, now: { 0 })
        XCTAssertEqual(result.url, "https://mail.google.com/mail/u/0/")
        XCTAssertEqual(result.depth, 26)
        XCTAssertEqual(result.source, "web_area")
    }

    func testCycleUsesCapturedWindowDocumentWithoutReadingOtherWindows() {
        var reads = 0
        let result = BrowserURLProbe.resolve(from: 0, sameNode: ==, read: { node in
            reads += 1
            return .init(url: nil, parent: 1 - node)
        }, documentURL: { "https://outlook.office.com/mail/" }, now: { 0 })
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(result.source, "window_document")
        XCTAssertEqual(result.url, "https://outlook.office.com/mail/")
    }

    func testLimitsAndNonWebDocumentsFailClosed() {
        var reads = 0
        let result = BrowserURLProbe.resolve(from: 0, sameNode: ==, read: { node in
            reads += 1
            return .init(url: nil, parent: node + 1)
        }, documentURL: { "file:///private/report.txt" }, now: { 0 })
        XCTAssertEqual(reads, 64)
        XCTAssertNil(result.url)
        XCTAssertEqual(result.source, "depth_limit")

        var time = 0.0
        let timed = BrowserURLProbe.resolve(from: 0, sameNode: ==, read: { node in
            time += 0.25
            return .init(url: nil, parent: node + 1)
        }, documentURL: { XCTFail("No fallback after deadline"); return nil }, now: { time })
        XCTAssertNil(timed.url)
        XCTAssertEqual(timed.depth, 1)
        XCTAssertEqual(timed.source, "time_limit")
    }

    func testNearestFrameWinsAndNoURLIsCachedBetweenCaptures() {
        for host in ["mail.google.com", "docs.google.com"] {
            let result = BrowserURLProbe.resolve(from: 0, sameNode: ==, read: { _ in
                .init(url: "https://\(host)/", parent: 1)
            }, documentURL: { "https://mail.google.com/" }, now: { 0 })
            XCTAssertEqual(result.url, "https://\(host)/")
        }
    }
}
