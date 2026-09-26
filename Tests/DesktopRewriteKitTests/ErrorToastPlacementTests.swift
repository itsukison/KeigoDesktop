import XCTest
@testable import DesktopRewriteKit

final class ErrorToastPlacementTests: XCTestCase {
    func testToastFollowsEveryZoneAndResizingAnchorOnOwningDisplay() {
        for area in [CGRect(x: 0, y: 78, width: 1512, height: 866),
                     CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                     CGRect(x: 1512, y: 300, width: 1280, height: 720)] {
            for zone in SnapZone.allCases {
                for anchorSize in [CGSize(width: 44, height: 28), CGSize(width: 208, height: 287),
                                   CGSize(width: 420, height: 440), CGSize(width: 320, height: 160)] {
                    let anchor = BarPlacement.zoneFrame(zone, barSize: anchorSize, workArea: area,
                        insets: BarSlotInsets(bottom: 6, top: 0, side: 0))
                    for height: CGFloat in [62, 100, 180, 62] {
                        let toast = BarPlacement.stackedFrame(size: CGSize(width: 360, height: height),
                            gap: 8, zone: zone, anchor: anchor, workArea: area)
                        XCTAssertTrue(area.contains(toast))
                        XCTAssertFalse(anchor.intersects(toast))
                        switch zone {
                        case .bottomCenter:
                            XCTAssertEqual(toast.minY, anchor.maxY + 8)
                            XCTAssertEqual(toast.midX, anchor.midX)
                        case .topCenter:
                            XCTAssertEqual(toast.maxY, anchor.minY - 8)
                            XCTAssertEqual(toast.midX, anchor.midX)
                        case .left:
                            XCTAssertEqual(toast.minX, anchor.maxX + 8)
                            XCTAssertEqual(toast.midY, anchor.midY)
                        case .right:
                            XCTAssertEqual(toast.maxX, anchor.minX - 8)
                            XCTAssertEqual(toast.midY, anchor.midY)
                        }
                    }
                }
            }
        }
    }

    func testZoneChangeDeterminesSideEvenBeforeAnchorMoves() {
        let area = CGRect(x: -1000, y: -300, width: 2000, height: 1200)
        let anchor = CGRect(x: -50, y: 200, width: 100, height: 100)
        let size = CGSize(width: 360, height: 100)
        let frames = SnapZone.allCases.map {
            BarPlacement.stackedFrame(size: size, gap: 8, zone: $0, anchor: anchor, workArea: area)
        }
        XCTAssertEqual(Set(frames.map { NSStringFromRect($0) }).count, 4)
        for frame in frames {
            XCTAssertTrue(area.contains(frame))
            XCTAssertFalse(frame.intersects(anchor))
        }
    }

    func testDockChangeAndHoverCollapseKeepGap() {
        for bottom: CGFloat in [0, 78, 0] {
            let area = CGRect(x: 0, y: bottom, width: 1920, height: 1080 - bottom)
            for size in [CGSize(width: 158, height: 34), CGSize(width: 44, height: 28)] {
                let anchor = BarPlacement.zoneFrame(.bottomCenter, barSize: size, workArea: area,
                    insets: BarSlotInsets(bottom: 6, top: 0, side: 0))
                let toast = BarPlacement.stackedFrame(size: CGSize(width: 360, height: 100),
                    gap: 8, zone: .bottomCenter, anchor: anchor, workArea: area)
                XCTAssertEqual(toast.minY, bottom + 6 + size.height + 8)
            }
        }
    }

    func testOversizedToastStaysInsideSmallOwningDisplay() {
        let area = CGRect(x: -320, y: 120, width: 320, height: 160)
        for zone in SnapZone.allCases {
            let toast = BarPlacement.stackedFrame(size: CGSize(width: 360, height: 180),
                gap: 8, zone: zone, anchor: CGRect(x: -24, y: 170, width: 24, height: 56), workArea: area)
            XCTAssertEqual(toast, area)
        }
    }
}
