#if DEBUG
import AppKit
import DesktopRewriteKit

@MainActor enum ReplyAvailabilityPreview {
    static var isRunning: Bool { ProcessInfo.processInfo.arguments.contains("--render-reply-availability") }

    static func render() async throws {
        let fixture = EdgePanelPreview()
        let controller = fixture.controller
        let output = URL(fileURLWithPath: "/private/tmp/keigo-reply-availability", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        await controller.refreshAccount()
        var report: [String] = []
        let clipboardCount = NSPasteboard.general.changeCount
        for language in AppLanguage.allCases {
            AppLanguageState.current = language
            let source = ReplySource(copied: tr(
                "明日の打ち合わせですが、午後3時からでも大丈夫でしょうか。ご都合をお知らせください。",
                "Would tomorrow at 3 pm work for our meeting? Please let me know what works for you.",
                "明天的会议改到下午三点可以吗？请告诉我您方便的时间。"))!
            for zone in SnapZone.allCases {
                controller.prepareReplyPreview(zone: zone)
                try await Task.sleep(for: .milliseconds(250))
                let panel = controller.replyPreviewPanel
                let collapsed = panel.frame
                controller.previewCopy(source)
                try await Task.sleep(for: .milliseconds(250))
                precondition(controller.state == .pill && !panel.canBecomeKey)
                precondition(panel.frame == collapsed && !controller.replyPreviewHasDetachedContext)
                try capture(panel, to: output, name: "\(language.rawValue)-\(zone.rawValue)-available")

                controller.mouseEntered()
                try await Task.sleep(for: .milliseconds(300))
                precondition(controller.state == .hoverRow && !panel.canBecomeKey)
                precondition(controller.availableReplySource == source && !controller.replyPreviewHasDetachedContext)
                try capture(panel, to: output, name: "\(language.rawValue)-\(zone.rawValue)-hover")
                controller.dismissReply()
                precondition(controller.state == .hoverRow && controller.availableReplySource == nil)
                controller.previewCopy(source)
                controller.mouseExited()
                try await Task.sleep(for: .milliseconds(450))
                precondition(controller.state == .pill && controller.availableReplySource == source)
                controller.mouseEntered()
                controller.previewReplyComposer()
                try await Task.sleep(for: .milliseconds(300))
                precondition(controller.state.replySource == source && panel.canBecomeKey)
                precondition(!controller.replyPreviewHasDetachedContext)
                let replacement = ReplySource(copied: "A different copied message should not replace the active reply.")!
                controller.previewCopy(replacement)
                precondition(controller.state.replySource == source)
                try capture(panel, to: output, name: "\(language.rawValue)-\(zone.rawValue)-composer")
                let expected = OverlayPlacement.zoneFrame(zone, barSize: panel.frame.size,
                    on: OverlayPlacement.screen(containing: panel.frame))
                precondition(abs(panel.frame.minX - expected.minX) < 1 && abs(panel.frame.minY - expected.minY) < 1)
                report.append("\(language.rawValue) \(zone.rawValue): collapsed \(NSStringFromRect(collapsed)); composer \(NSStringFromRect(panel.frame))")
                controller.cancelInput()
                precondition(!controller.state.wantsKeyWindow && controller.availableReplySource?.text == source.text)
                controller.dismissReply()
                precondition(controller.availableReplySource == nil)
                controller.previewCopy(ReplySource(copied: source.text, at: Date().addingTimeInterval(-181)))
                precondition(controller.availableReplySource == nil)
                controller.previewCopy(ReplySource(copied: source.text, at: Date().addingTimeInterval(-179.9)))
                try await Task.sleep(for: .milliseconds(200))
                precondition(controller.availableReplySource == nil)
                controller.previewCopy(source)
                controller.previewCopy(nil)
                precondition(controller.availableReplySource == nil)
            }
        }
        precondition(NSPasteboard.general.changeCount == clipboardCount)
        report.append("PASS: 12 native layouts; unchanged collapsed geometry; non-key hover; hover dismissal; grace collapse; attached source; frozen composer source; cancellation; expiry; invalid-copy clearing; clipboard preserved.")
        report.append("Composer capture used a scratch fixture; cross-app capture/insertion and live backend were not exercised.")
        try report.joined(separator: "\n").write(to: output.appendingPathComponent("verification.txt"), atomically: true, encoding: .utf8)
        controller.setVisible(false)
    }

    private static func capture(_ panel: NSPanel, to output: URL, name: String) throws {
        let host = panel.contentView!
        host.layoutSubtreeIfNeeded()
        let size = host.bounds.size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
    }
}
#endif
