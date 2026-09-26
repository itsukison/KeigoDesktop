import AppKit
import DesktopRewriteKit
import SwiftUI

/// Retained for dormant explicit context capture. Shipping copied replies render
/// their source inside PillPanel instead. This separate panel is bounded and never key.
final class ReplyContextPanel: NSPanel {

    /// Which copy this card is showing. `OverlayController` compares it to decide
    /// between re-anchoring the existing card and building a new one.
    let source: ReplySource?

    /// The bar's frame, as last known. The only input to `applyFrame`.
    private var anchor: NSRect

    init(anchor: NSRect, source: ReplySource?, controller: OverlayController? = nil, onDismiss: @escaping () -> Void) {
        self.source = source
        self.anchor = anchor
        super.init(
            contentRect: Self.frame(anchoredTo: anchor),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none

        contentView = NSHostingView(
            rootView: Group {
                if let controller { ExplicitReplyContextPill(controller: controller, onDismiss: onDismiss) }
                else if let source { ReplyContextPill(source: source, onDismiss: onDismiss) }
            }
        )
    }

    /// Sits `replyContextGap` beyond the bar's near edge, centred on it, at the
    /// composer's width so the two line up as one column once the input box opens —
    /// on whichever side of the bar has more room, so a bar parked at the top of the
    /// screen carries its card below it instead of losing it to the clamp.
    static func frame(anchoredTo anchor: NSRect) -> NSRect {
        OverlayPlacement.stackedFrame(
            size: NSSize(
                width: Tokens.Geometry.inputBarWidth,
                height: Tokens.Geometry.replyContextHeight
            ),
            gap: Tokens.Geometry.replyContextGap,
            anchoredTo: anchor
        )
    }

    /// Follows the bar. The input bar wraps to `inputBarMaxLines` as the user types, so
    /// the thing this pill sits on top of gets taller *during* composition — pinned at
    /// creation it would be grown into by the second line.
    func reanchor(to anchor: NSRect) {
        self.anchor = anchor
        let target = Self.frame(anchoredTo: anchor)
        guard target != frame else { return }
        setFrame(target, display: true)
        invalidateShadow()
    }

    /// Never key. `OverlayController.panelResignedKey` cancels the composer when
    /// `PillPanel` loses key, so a pill that could take focus would close the input bar
    /// the moment anyone clicked the message they were reading.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// `[↩]  the copied message, in italic  [✕]` — one row, the same capsule as the bar.
struct ReplyContextPill: View {
    let source: ReplySource
    let onDismiss: () -> Void

    @State private var isHoveringDismiss = false

    var body: some View {
        HStack(spacing: 8) {
            // Carries what a 「返信先」 label used to say. On one line the label and the
            // icon are the same word twice, and the message needs the width more.
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Tokens.Overlay.textTertiary)

            // Italic because it is a quotation — someone else's words, sitting above
            // the field where yours go. It is also the one thing separating it from the
            // bar's own labels at a glance.
            Text(source.contextText)
                .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                .italic()
                .foregroundStyle(Tokens.Overlay.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(
                        isHoveringDismiss
                            ? Tokens.Overlay.textPrimary
                            : Tokens.Overlay.textTertiary
                    )
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringDismiss = $0 }
            .cursor(.pointingHand)
        }
        .padding(.horizontal, 12)
        // Fills the window exactly. The window's height is the token, not a
        // measurement, so nothing here may ask to be taller than it.
        .frame(
            width: Tokens.Geometry.inputBarWidth,
            height: Tokens.Geometry.replyContextHeight
        )
        .background(SmokedGlassSurface(shape: Capsule()))
    }
}

struct ExplicitReplyContextPill: View {
    @ObservedObject var controller: OverlayController
    let onDismiss: () -> Void

    private var label: String {
        guard let session = controller.replySession else { return "" }
        switch session.phase {
        case .loading:
            return session.queuedGuidance == nil
                ? tr("会話を確認中… 指示を入力できます", "Finding conversation… you can type", "正在识别对话…可输入要求")
                : tr("会話を確認後、返信を作成します…", "Will generate when context is ready…", "识别完成后将生成回复…")
        case .unavailable:
            switch session.failureReason {
            case "missing_current_history": return tr("最近のメッセージを表示して、返信を押し直してください", "Show recent messages and press Reply again", "请显示最近的消息后重新点击回复")
            case "capture_incomplete": return tr("会話を開いて、返信を押し直してください", "Open the conversation and press Reply again", "请打开对话后重新点击回复")
            case "unauthorized": return tr("サインインし直してください", "Sign in again to analyze context", "请重新登录以分析对话")
            case "analysis_budget", "capture_budget", "payload_too_large", "candidate_coverage": return tr("会話の範囲が広すぎます", "Conversation exceeds analysis limits", "对话范围超出分析限制")
            case "context_rate_limited", "provider_rate_limited": return tr("少し待ってから再試行してください", "Please wait before retrying", "请稍后重试")
            case "provider_not_configured": return tr("会話解析の設定が必要です", "Conversation analysis needs setup", "对话分析尚未配置")
            case "context_timeout": return tr("会話の確認がタイムアウトしました", "Conversation analysis timed out", "对话分析超时")
            case "no_readable_context", "no_conversation": return tr("会話が見つかりませんでした", "No readable conversation found", "未找到可读取的对话")
            default: return tr("会話の確認に失敗しました。再試行できます", "Analysis failed · retry available", "对话分析失败，可重试")
            }
        case .needsSource:
            if session.failureReason == "ambiguous_audience" {
                return tr("個別かグループか確認できませんでした", "Couldn’t determine direct or group reply", "无法确定是私聊还是群聊")
            }
            return tr("返信先を特定できませんでした", "Couldn’t identify the reply context", "无法确定要回复的对话")
        case .ready:
            return (session.context?.completeness == .partial ? tr("一部 · ", "Partial · ", "部分 · ") : "")
                + (session.context?.selectedTargetText ?? "").replacingOccurrences(of: "\n", with: " ")
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(String(label.prefix(500)))
                .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                .foregroundStyle(Tokens.Overlay.textSecondary)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Menu(tr("変更", "Change", "更改")) {
                if controller.replySession?.canRetryAnalysis == true {
                    Button(tr("再試行", "Retry analysis", "重试分析")) { controller.retryReplyContext() }
                }
                if let session = controller.replySession, let evidence = session.evidence {
                    // Choose a visible source first; analysis still determines audience and targets.
                    ForEach(session.suggestedRegionIDs.isEmpty ? Array(Set(evidence.blocks.map(\.conversationId))).sorted().prefix(4).map { $0 } : session.suggestedRegionIDs, id: \.self) { id in
                        let blocks = session.blocks(in: id)
                        Button(String((blocks.first?.text ?? "").prefix(70))) { controller.chooseReplyRegion(id) }
                    }
                }
                #if DEBUG
                Button("Export Reply Diagnostics…") { controller.exportReplyDiagnostics() }
                Divider()
                #endif
                Menu(tr("手動で指定", "Choose manually", "手动指定")) {
                ForEach([ReplyAudienceKind.direct, .group], id: \.rawValue) { audience in
                    Menu(audience == .direct ? tr("個別の会話", "Direct conversation", "私聊") : tr("グループ", "Group conversation", "群聊")) {
                        Button(tr("コピーした内容を使用", "Use copied message", "使用已复制的消息")) { controller.pasteReplySource(audience: audience) }
                        if let evidence = controller.replySession?.evidence {
                            ForEach(Array(Set(evidence.blocks.map(\.conversationId))).sorted(), id: \.self) { id in
                                let blocks = evidence.blocks.filter { $0.conversationId == id }
                                Button(tr("会話: ", "Conversation: ", "对话：") + String((blocks.first?.text ?? "").prefix(60))) {
                                    controller.chooseReplySource(blocks, audience: audience)
                                }
                            }
                            Divider()
                            ForEach(evidence.blocks, id: \.id) { block in
                                Button(String(block.text.prefix(90))) { controller.chooseReplySource([block], audience: audience) }
                            }
                        }
                    }
                }
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(controller.replySession?.phase == .loading)
            .cursor(controller.replySession?.phase == .loading ? .arrow : .pointingHand)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
        }
        .padding(.horizontal, 12)
        .frame(width: Tokens.Geometry.inputBarWidth, height: Tokens.Geometry.replyContextHeight)
        .background(SmokedGlassSurface(shape: Capsule()))
        .foregroundStyle(Tokens.Overlay.textSecondary)
        .preferredColorScheme(.dark)
    }
}
