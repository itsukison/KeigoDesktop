import ApplicationServices
import XCTest
@testable import TextIO

final class ConversationTextReadTests: XCTestCase {
    private func read(_ value: (String?, AXError), _ title: (String?, AXError)) -> ConversationTextRead {
        ConversationTextRead.read(attributes: ["AXValue", "AXTitle"]) { $0 == "AXValue" ? value : title }
    }

    func testSuccessfulEmptyOrWhitespaceReadSurvivesUnsupportedFallback() {
        for value in ["", " ", "\n\t", "\u{00a0}"] {
            let result = read((value, .success), (nil, .attributeUnsupported))
            XCTAssertEqual(result.text, "")
            XCTAssertEqual(result.sourceAttribute, "AXValue")
            XCTAssertTrue(result.failedAttributes.isEmpty)
        }
    }

    func testBlankPrimaryStillAllowsMeaningfulFallback() {
        let result = read((" ", .success), ("Exact title text", .success))
        XCTAssertEqual(result.text, "Exact title text")
        XCTAssertEqual(result.sourceAttribute, "AXTitle")
    }

    func testMissingValuesAreNotCertifiedEmpty() {
        let result = read((nil, .noValue), (nil, .attributeUnsupported))
        XCTAssertNil(result.text)
        XCTAssertNil(result.sourceAttribute)
    }

    func testFailedReadCannotBeHiddenByBlankFallbackOrPrimary() {
        for result in [read((nil, .cannotComplete), ("", .success)), read(("", .success), (nil, .cannotComplete))] {
            XCTAssertNil(result.text)
            XCTAssertEqual(result.failedAttributes.count, 1)
            XCTAssertEqual(result.axErrorCodes, [Int(AXError.cannotComplete.rawValue)])
        }
        XCTAssertNil(read((nil, .success), ("", .success)).text)
    }

    func testNonblankPrimaryPreservesExactTextAndDoesNotReadFallback() {
        var names: [String] = []
        let result = ConversationTextRead.read(attributes: ["AXValue", "AXTitle"]) { name in
            names.append(name)
            return ("  Message\n", .success)
        }
        XCTAssertEqual(result.text, "  Message\n")
        XCTAssertEqual(names, ["AXValue"])
    }
}
