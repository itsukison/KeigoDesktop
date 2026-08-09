import XCTest
@testable import TextIO

final class AXWriteSchedulingTests: XCTestCase {
    func testSameProcessAXWriteUsesMainActor() {
        XCTAssertTrue(AXTextIO.writeRequiresMainActor(targetPID: 42, currentPID: 42))
    }

    func testCrossProcessAXWriteStaysOffMainActor() {
        XCTAssertFalse(AXTextIO.writeRequiresMainActor(targetPID: 42, currentPID: 84))
    }
}
