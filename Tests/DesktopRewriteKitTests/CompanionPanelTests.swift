import XCTest
@testable import DesktopRewriteKit

final class CompanionPanelTests: XCTestCase {
    func testReplacementKeepsAttachmentAcrossContentSizesAndDisplays() {
        let insets = BarSlotInsets(bottom: 6, top: 0, side: 0)
        for area in [CGRect(x: 0, y: 78, width: 1512, height: 866),
                     CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                     CGRect(x: 1512, y: 300, width: 1280, height: 720)] {
            for zone in SnapZone.allCases {
                let anchor = BarPlacement.zoneFrame(zone, barSize: CGSize(width: 208, height: 48),
                                                    workArea: area, insets: insets)
                for height: CGFloat in [36, 60, 124, 240, 440, 520, 124] {
                    let width: CGFloat = zone == .left || zone == .right ? 320 : 420
                    let frame = BarPlacement.attachedFrame(size: CGSize(width: width, height: height),
                                                          zone: zone, anchor: anchor, workArea: area)
                    XCTAssertTrue(area.contains(frame))
                    switch zone {
                    case .left:
                        XCTAssertEqual(frame.minX, anchor.minX)
                        XCTAssertEqual(frame.midY, anchor.midY)
                    case .right:
                        XCTAssertEqual(frame.maxX, anchor.maxX)
                        XCTAssertEqual(frame.midY, anchor.midY)
                    case .topCenter:
                        XCTAssertEqual(frame.maxY, anchor.maxY)
                        XCTAssertEqual(frame.midX, anchor.midX)
                    case .bottomCenter:
                        XCTAssertEqual(frame.minY, anchor.minY)
                        XCTAssertEqual(frame.midX, anchor.midX)
                    }
                }
            }
        }
    }

    func testNotchCenterAndBottomSurviveGrowth() {
        let area = CGRect(x: -1512, y: 0, width: 1512, height: 944)
        let notch = CGRect(x: -856, y: 944, width: 200, height: 38)
        let anchor = BarPlacement.zoneFrame(.topCenter, barSize: CGSize(width: 200, height: 28),
            workArea: area, insets: BarSlotInsets(bottom: 6, top: 0, side: 0), notch: notch)
        for size in [CGSize(width: 208, height: 40), CGSize(width: 420, height: 150), CGSize(width: 420, height: 440)] {
            let frame = BarPlacement.attachedFrame(size: size, zone: .topCenter, anchor: anchor, workArea: area)
            XCTAssertEqual(frame.maxY, notch.minY)
            XCTAssertEqual(frame.midX, notch.midX)
        }
    }

    func testOversizedPanelFitsWorkAreaWithoutEscapingOntoNeighbor() {
        let area = CGRect(x: -320, y: 120, width: 320, height: 300)
        for zone in SnapZone.allCases {
            let frame = BarPlacement.attachedFrame(size: CGSize(width: 420, height: 440), zone: zone,
                anchor: CGRect(x: -200, y: 200, width: 24, height: 56), workArea: area)
            XCTAssertEqual(frame, area)
        }
    }

    func testDockChangeReanchorsFromNewSlotRatherThanPreviousResult() {
        let full = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let dock = CGRect(x: 0, y: 78, width: 1920, height: 1002)
        for area in [full, dock, full] {
            let anchor = BarPlacement.zoneFrame(.bottomCenter, barSize: CGSize(width: 44, height: 28),
                workArea: area, insets: BarSlotInsets(bottom: 6, top: 0, side: 0))
            let result = BarPlacement.attachedFrame(size: CGSize(width: 420, height: 240),
                zone: .bottomCenter, anchor: anchor, workArea: area)
            XCTAssertEqual(result.minY, area.minY + 6)
        }
    }

    func testInstructionsRemainExplicitAcrossRegenerationAndRefinement() {
        let polish = ResultInstruction.hidden
        XCTAssertNil(polish.regenerated(edit: nil).text)
        let automaticReply = ResultInstruction.input(" \n ")
        XCTAssertNil(automaticReply.regenerated(edit: nil).text)
        let custom = ResultInstruction.input("  Keep it friendly  ")
        XCTAssertEqual(custom.regenerated(edit: nil).text, "Keep it friendly")
        let edited = custom.regenerated(edit: "Shorter")
        XCTAssertEqual(edited.regenerated(edit: nil).text, "Shorter")
        let refinedPolish = polish.regenerated(edit: "Add a thank you")
        XCTAssertEqual(refinedPolish.text, "Add a thank you")
        XCTAssertEqual(polish, .hidden)
        XCTAssertEqual(custom.text, "Keep it friendly")
    }
}
