import AppKit
import DesktopRewriteKit
import SwiftUI

extension OnboardingLesson {
    func instruction(copyOnly: Bool = false) -> String {
        switch phase {
        case .source:
            return ReplyContextFeature.isEnabled
                ? tr("このメッセージを選びましょう", "Select this message", "选择这条消息")
                : tr("このメッセージをコピーしましょう", "Copy this message", "复制这条消息")
        case .focus: return tr("練習用の本文をクリック", "Click inside the sample message", "点击练习消息的正文")
        case .restore: return tr("練習用の文章を戻しましょう", "Restore the sample message", "恢复练习消息")
        case .hover: return tr("バーにカーソルを合わせましょう", "Move your pointer onto the bar", "将光标移到工具条上")
        case .discovered: return tr("これがバーです。使ってみましょう", "That’s your bar. Let’s try it.", "这就是工具条。试试看吧。")
        case .action:
            switch kind {
            case .rewrite: return tr("書き換えボタンをクリック", "Click a rewrite button", "点击改写按钮")
            case .custom: return tr("鉛筆のボタンをクリック", "Click the pencil", "点击铅笔按钮")
            case .reply:
                return tr("「返信」をクリック", "Click “Reply”", "点击「回复」")
            case .discovery: return tr("バーにカーソルを合わせましょう", "Move your pointer onto the bar", "将光标移到工具条上")
            }
        case .instruction:
            return kind == .reply
                ? tr("どんな返信にするか入力", "Type how you want to reply", "输入你想怎样回复")
                : tr("指示を入力しましょう", "Type an instruction", "输入一个要求")
        case .submit: return tr("Return キーで生成", "Press Return to generate", "按 Return 键生成")
        case .generating:
            return kind == .reply ? tr("返信を作っています…", "Writing your reply…", "正在生成回复…")
                : tr("文章を整えています…", "Polishing your message…", "正在润色消息…")
        case .result:
            return copyOnly ? tr("「コピー」をクリック", "Click “Copy”", "点击「复制」")
                : tr("「挿入」で文章を置き換えましょう", "Click “Insert” to replace the sample text", "点击「插入」替换练习文字")
        case .complete(.copied): return tr("コピーできました", "Copied. Paste it where you need it.", "已复制。请粘贴到需要的位置。")
        case .complete(.inserted):
            switch kind {
            case .reply: return tr("できました！返信が入りました", "Done! Your reply is in.", "完成！回复已插入。")
            case .custom: return tr("できました！指示どおりに整いました", "Done! You used your own instruction.", "完成！已按你的要求润色。")
            default: return tr("できました！文章が整いました", "Done! You polished your first message.", "完成！你润色了第一条消息。")
            }
        }
    }

    var supportingText: String {
        if needsRetry && phase != .result {
            return tr("もう一度試せます。練習用の文章はそのままです。", "Try again. Your sample message is still here.", "可以重试。练习消息仍保留在这里。")
        }
        switch phase {
        case .hover: return tr("カーソルを合わせると、バーが開きます。", "It opens when you hover over it.", "光标悬停后，工具条会展开。")
        case .discovered: return tr("「書き換えを練習」で、実際に試せます。", "Choose “Try a rewrite” to practice.", "点击「练习改写」开始练习。")
        case .instruction, .submit:
            return kind == .reply
                ? tr("例：「参加できると伝えて」", "Try: “Say I can attend.”", "例如：「告诉对方我可以参加。」")
                : tr("例：「もっと短くして」", "Try: “Make it shorter.”", "例如：「写短一点。」")
        case .complete(.copied): return tr("貼り付けたい場所で ⌘V を押してください。", "Press ⌘V where you want to paste it.", "在需要粘贴的位置按 ⌘V。")
        case .complete(.inserted): return tr("同じ操作を、いつものアプリでも使えます。", "Use the same steps in your everyday apps.", "在常用应用中也可以这样操作。")
        case .source: return tr("メッセージの下のボタンを押してください。", "Use the button beneath the message.", "点击消息下方的按钮。")
        case .focus: return tr("本文をクリックしてから、バーに戻ります。", "Click the message, then move back to the bar.", "点击正文，然后回到工具条。")
        case .restore: return tr("「文章を戻す」で、もう一度練習できます。", "Choose “Restore sample” to try again.", "点击「恢复示例」重新练习。")
        case .result: return tr("結果を確認してから、下のボタンを押してください。", "Read the result, then use its bottom button.", "查看结果，然后点击下方按钮。")
        case .action: return tr("実際のバーで、明るいボタンを押してください。", "Use the highlighted button on the real bar.", "点击真实工具条上高亮的按钮。")
        case .generating: return tr("結果が出るまで、そのままお待ちください。", "Your result will appear in a moment.", "请稍候，结果即将出现。")
        }
    }

    var progressLabel: String {
        let label: String
        switch kind {
        case .discovery: label = tr("バーを見つける", "Find your bar", "找到工具条")
        case .rewrite: label = tr("書き換えの練習", "Rewrite practice", "练习改写")
        case .custom: label = tr("指示の練習", "Custom practice", "练习自定义要求")
        case .reply: label = tr("返信の練習", "Reply practice", "练习回复")
        }
        return label
    }

    var guideAnchor: LessonAnchor? {
        switch phase {
        case .hover: return .bar
        case .action:
            switch kind {
            case .rewrite: return .polish
            case .custom: return .custom
            case .reply: return .reply
            case .discovery: return .bar
            }
        case .instruction, .submit: return .composer
        case .result: return .result
        default: return nil
        }
    }
}

struct LessonHeading: View {
    let lesson: OnboardingLesson
    var copyOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lesson.progressLabel)
                .font(Tokens.LightFont.body(13, weight: .semibold))
                .foregroundStyle(Tokens.Window.accentText)
            Text(lesson.instruction(copyOnly: copyOnly))
                .font(Tokens.LightFont.body(28, weight: .semibold))
                .foregroundStyle(Tokens.Window.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(lesson.supportingText)
                .font(Tokens.LightFont.Onboarding.body)
                .foregroundStyle(Tokens.Window.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
        .onChange(of: lesson.instruction(copyOnly: copyOnly)) { _, text in
            guard let window = NSApp.keyWindow else { return }
            NSAccessibility.post(element: window, notification: .announcementRequested,
                userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
}
