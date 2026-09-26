import XCTest
@testable import DesktopRewriteKit

/// Pins `docs/bar-positioning.md`'s growth table and the slot geometry behind the
/// snap picker. The one thing these tests protect against is the failure the plan
/// was written for: something hardcoding "the bar is at the bottom, grow upward"
/// back into a helper whose whole job is not to.
final class BarPlacementTests: XCTestCase {

    // 1920×1080 with no Dock — the numbers are easier to read than the Dock-present
    // variant and the math under test does not care where the area came from.
    private let workArea = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let insets = BarSlotInsets(bottom: 6, top: 6, side: 6)
    private let barSize = CGSize(width: 44, height: 28)
    private let edgeThreshold: CGFloat = 120

    private func zoneFrame(_ zone: SnapZone) -> CGRect {
        BarPlacement.zoneFrame(zone, barSize: barSize, workArea: workArea, insets: insets)
    }

    private func activeZone(_ bar: CGRect) -> SnapZone? {
        BarPlacement.activeZone(
            near: bar,
            workArea: workArea,
            insets: insets,
            edgeThreshold: edgeThreshold
        )
    }

    // MARK: - Slot geometry

    func testZoneFramesMatchTheGrowthTable() {
        XCTAssertEqual(zoneFrame(.bottomCenter), CGRect(x: 938, y: 6, width: 44, height: 28))
        XCTAssertEqual(zoneFrame(.topCenter), CGRect(x: 938, y: 1046, width: 44, height: 28))
        XCTAssertEqual(zoneFrame(.left), CGRect(x: 6, y: 526, width: 44, height: 28))
        XCTAssertEqual(zoneFrame(.right), CGRect(x: 1870, y: 526, width: 44, height: 28))
    }

    func testZoneFramesFollowTheWorkAreaNotTheScreen() {
        // A Dock-sized work area shifts every bottom slot up and every top slot stays
        // under the menu bar edge — the slots are relative, which is what makes a
        // stored zone survive a Dock appearing or a display swap.
        let dockArea = CGRect(x: 0, y: 78, width: 1920, height: 1002)
        let frame = BarPlacement.zoneFrame(.bottomCenter, barSize: barSize, workArea: dockArea, insets: insets)
        XCTAssertEqual(frame, CGRect(x: 938, y: 84, width: 44, height: 28))
    }

    func testZoneFrameClampsWhenTheBarOutgrowsTheArea() {
        let narrow = CGRect(x: 0, y: 0, width: 100, height: 1080)
        let wide = CGSize(width: 400, height: 34)
        let frame = BarPlacement.zoneFrame(.bottomCenter, barSize: wide, workArea: narrow, insets: insets)
        XCTAssertEqual(frame, CGRect(x: min(938, 100 - 400), y: 6, width: 400, height: 34))
    }

    func testNotchTabJoinsHousingAndExpandsDownward() {
        let area = CGRect(x: -1512, y: 78, width: 1512, height: 866)
        let notch = CGRect(x: -846, y: 944, width: 180, height: 38)
        let flush = BarSlotInsets(bottom: 6, top: 0, side: 0)
        for size in [CGSize(width: 180, height: 28), CGSize(width: 360, height: 44)] {
            let frame = BarPlacement.zoneFrame(.topCenter, barSize: size,
                workArea: area, insets: flush, notch: notch)
            XCTAssertEqual(frame.maxY, notch.minY)
            XCTAssertEqual(frame.midX, notch.midX)
            XCTAssertTrue(area.contains(frame))
        }
    }

    func testSideExpansionKeepsItsEdgeAndVerticalCenter() {
        let flush = BarSlotInsets(bottom: 6, top: 0, side: 0)
        for size in [CGSize(width: 24, height: 56), CGSize(width: 300, height: 34)] {
            let left = BarPlacement.zoneFrame(.left, barSize: size, workArea: workArea, insets: flush)
            let right = BarPlacement.zoneFrame(.right, barSize: size, workArea: workArea, insets: flush)
            XCTAssertEqual(left.minX, workArea.minX)
            XCTAssertEqual(right.maxX, workArea.maxX)
            XCTAssertEqual(left.midY, workArea.midY)
            XCTAssertEqual(right.midY, workArea.midY)
        }
    }

    // MARK: - Snap proximity

    func testExactlyFourDestinationsAndLegacyMigration() {
        XCTAssertEqual(SnapZone.allCases, [.bottomCenter, .topCenter, .left, .right])
        XCTAssertEqual(SnapZone.restored(from: "topLeft"), .topCenter)
        XCTAssertEqual(SnapZone.restored(from: "topRight"), .topCenter)
        XCTAssertEqual(SnapZone.restored(from: "bottomLeft"), .bottomCenter)
        XCTAssertEqual(SnapZone.restored(from: "bottomRight"), .bottomCenter)
        XCTAssertEqual(SnapZone.restored(from: nil), .bottomCenter)
        XCTAssertEqual(SnapZone.restored(from: "invalid"), .bottomCenter)
        XCTAssertEqual(SnapZone.restored(from: "left"), .left)
    }

    func testBarHeldOverEverySlotSnapsToIt() {
        for zone in SnapZone.allCases {
            XCTAssertEqual(activeZone(zoneFrame(zone)), zone)
        }
    }

    func testGenerousTargetsDoNotRequireAnExactDrop() {
        XCTAssertEqual(activeZone(zoneFrame(.bottomCenter).offsetBy(dx: 100, dy: 65)), .bottomCenter)
        XCTAssertEqual(activeZone(zoneFrame(.left).offsetBy(dx: 80, dy: 80)), .left)
        XCTAssertEqual(activeZone(zoneFrame(.topCenter).offsetBy(dx: -90, dy: -65)), .topCenter)
    }

    func testDistantReleaseAndFormerCornersHaveNoTarget() {
        XCTAssertNil(activeZone(CGRect(x: 900, y: 500, width: 44, height: 28)))
        XCTAssertNil(activeZone(CGRect(x: 6, y: 6, width: 44, height: 28)))
        XCTAssertNil(activeZone(CGRect(x: 6, y: 1046, width: 44, height: 28)))
    }

    func testSnappingOnOffsetDisplay() {
        let area = workArea.offsetBy(dx: -1920, dy: 400)
        let bar = BarPlacement.zoneFrame(.right, barSize: barSize, workArea: area, insets: insets)
        XCTAssertEqual(BarPlacement.activeZone(near: bar.offsetBy(dx: -80, dy: 20),
            workArea: area, insets: insets, edgeThreshold: edgeThreshold), .right)
    }

    // MARK: - Growth direction

    func testVerticalSideFollowsRoom() {
        let bottom = CGRect(x: 938, y: 6, width: 44, height: 28)
        XCTAssertEqual(BarPlacement.verticalSide(ofBar: bottom, in: workArea), .above)

        let top = CGRect(x: 938, y: 1046, width: 44, height: 28)
        XCTAssertEqual(BarPlacement.verticalSide(ofBar: top, in: workArea), .below)
    }

    func testVerticalSideTieStaysAbove() {
        // Exactly centred vertically: room above == room below. `.above` preserves
        // the pre-zone behaviour of every panel, so the tie must not flip it.
        let centred = CGRect(x: 938, y: 526, width: 44, height: 28)
        XCTAssertEqual(BarPlacement.verticalSide(ofBar: centred, in: workArea), .above)
    }

    func testReplaceFrameGrowsThroughTheBarAwayFromTheEdge() {
        let bottomBar = CGRect(x: 938, y: 6, width: 44, height: 28)
        let panel = CGSize(width: 420, height: 440)
        // Bottom: the panel's bottom edge is the bar's bottom line — today's
        // behaviour, unchanged.
        var frame = BarPlacement.replaceFrame(size: panel, bar: bottomBar, workArea: workArea)
        XCTAssertEqual(frame.minY, bottomBar.minY)

        // Top: the mirror — the panel's TOP edge is the bar's top line, so it hangs
        // below the bar instead of being clamped back down the screen away from it.
        let topBar = CGRect(x: 938, y: 1046, width: 44, height: 28)
        frame = BarPlacement.replaceFrame(size: panel, bar: topBar, workArea: workArea)
        XCTAssertEqual(frame.maxY, topBar.maxY)
    }

    func testReplaceFrameClampsTowardTheRoomySide() {
        // A panel taller than all the room above a mid-height bar slides down until
        // it fits, still centred on the bar horizontally.
        let midBar = CGRect(x: 938, y: 540, width: 44, height: 28)
        let tall = CGSize(width: 420, height: 1000)
        let frame = BarPlacement.replaceFrame(size: tall, bar: midBar, workArea: workArea)
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.maxY, 1000)
        XCTAssertEqual(frame.midX, midBar.midX)
    }

    func testStackedFrameSitsGapBeyondTheNearEdge() {
        let card = CGSize(width: 360, height: 62)
        let bar = CGRect(x: 780, y: 6, width: 360, height: 28)

        var frame = BarPlacement.stackedFrame(size: card, gap: 8, anchor: bar, workArea: workArea)
        XCTAssertEqual(frame.minY, bar.maxY + 8)

        // The same bar's frame reflected to the top of the screen: the card now sits
        // BELOW it, its top edge `gap` under the bar's bottom.
        let topBar = CGRect(x: 780, y: 1046, width: 360, height: 28)
        frame = BarPlacement.stackedFrame(size: card, gap: 8, anchor: topBar, workArea: workArea)
        XCTAssertEqual(frame.maxY, topBar.minY - 8)
    }

    func testStackedFrameCentresOnTheAnchor() {
        let card = CGSize(width: 360, height: 62)
        let bar = CGRect(x: 780, y: 6, width: 360, height: 28)
        let frame = BarPlacement.stackedFrame(size: card, gap: 8, anchor: bar, workArea: workArea)
        XCTAssertEqual(frame.midX, bar.midX)
    }
}
