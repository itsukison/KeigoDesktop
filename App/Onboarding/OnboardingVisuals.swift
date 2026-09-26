import DesktopRewriteKit
import SwiftUI

struct OnboardingVisualStage<Content: View>: View {
    var artwork: AsideBackdrop.Artwork = .mountain
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            AsideBackdrop(artwork: artwork)
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Shared bounds keep illustration edges stable across account, name and access.
struct OnboardingSplitPage<Copy: View, Visual: View>: View {
    @ViewBuilder var copy: () -> Copy
    @ViewBuilder var visual: () -> Visual
    var body: some View {
        HStack(spacing: 32) {
            GeometryReader { geometry in
                ScrollView {
                    copy()
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: 420)
            visual().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct OnboardingChoicePage<Content: View>: View {
    var width: CGFloat = 560
    @ViewBuilder var content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) { content() }
                    .frame(width: width)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct OnboardingMailScene<Editor: View>: View {
    let labels: [String]
    var showsBar = true
    var barExpanded = true
    @ViewBuilder var editor: () -> Editor

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = showsBar ? max(18, proxy.size.width * 0.055) : 24
            let bottomInset = showsBar ? max(44, proxy.size.height * 0.16) : 24

            ZStack(alignment: .bottom) {
                OnboardingMailWindow(editor: editor)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, showsBar ? max(18, proxy.size.height * 0.07) : 24)
                    .padding(.bottom, bottomInset)

                if showsBar {
                    OnboardingOverlayBar(labels: labels, expanded: barExpanded)
                        .padding(.bottom, max(14, proxy.size.height * 0.035))
                }
            }
        }
    }
}

struct OnboardingMailWindow<Editor: View>: View {
    @ViewBuilder var editor: () -> Editor

    var body: some View {
        VStack(spacing: 0) {
            MockWindowChrome(title: tr("メール — 新規メッセージ", "Mail — New Message", "邮件 — 新邮件"))

            HStack(spacing: 14) {
                MockToolbarButton(icon: .edit, title: tr("送信", "Send", "发送"))
                MockToolbarButton(icon: .copy, title: tr("下書き", "Draft", "草稿"))
                Spacer()
                Icon(.close, size: 12)
                    .foregroundStyle(Tokens.Window.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Tokens.Window.surfaceHover)

            MailHeaderRow(label: tr("宛先", "To", "收件人"), value: tr("佐藤さん", "Sam Rivera", "佐藤さん"))
            Hairline()
            MailHeaderRow(label: tr("件名", "Subject", "主题"), value: tr("明日の打ち合わせについて", "Tomorrow's meeting", "关于明天的会议"))
            Hairline()

            editor()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.09))
        )
        .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
    }
}

struct OnboardingSlackScene<Composer: View>: View {
    let message: String
    let copied: Bool
    let onCopy: () -> Void
    @ViewBuilder var composer: () -> Composer

    var body: some View {
        VStack(spacing: 0) {
            MockWindowChrome(title: "Slack — # product").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image("LogoSlack").resizable().scaledToFit().frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aki Matsuda").font(Tokens.LightFont.body(14, weight: .medium))
                        Text(message).font(Tokens.LightFont.Onboarding.instruction)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: onCopy) {
                            Label(ReplyContextFeature.isEnabled
                                ? (copied ? tr("選択済み", "Selected", "已选择") : tr("このメッセージを選択", "Select this message", "选择这条消息"))
                                : (copied ? tr("コピーしました", "Copied", "已复制") : tr("メッセージをコピー", "Copy message", "复制消息")),
                                systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font(Tokens.LightFont.Onboarding.action)
                                .foregroundStyle(copied ? Tokens.Window.success : Tokens.Window.accentText)
                                .padding(.horizontal, 12).frame(height: 40)
                                .background(Tokens.Window.accentTint, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(LightPressStyle()).disabled(copied)
                    }
                }
                Spacer(minLength: 0)
                Text(tr("あなたの返信", "Your reply", "你的回复"))
                    .font(Tokens.LightFont.Onboarding.caption)
                    .foregroundStyle(Tokens.Window.textSecondary)
                composer().frame(minHeight: 76, maxHeight: .infinity)
                    .background(.white)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.Window.borderControl))
            }
            .padding(24)
        }
        .foregroundStyle(Tokens.Window.textPrimary)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .padding(24)
    }
}

private struct SlackSidebarRow: View {
    let title: String
    var selected = false

    var body: some View {
        Text(title)
            .font(Tokens.LightFont.body(11, weight: selected ? .medium : .regular))
            .foregroundStyle(.white.opacity(selected ? 1 : 0.72))
            .padding(.horizontal, 14)
            .frame(height: 27)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

struct OnboardingStaticMailBody: View {
    let text: String
    var focused = true

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("佐藤さん", "Sam Rivera", "佐藤さん"))
            Text(text)
            Text(tr("よろしくお願いします。", "Thanks!", "拜托了。"))
            Spacer(minLength: 0)
        }
        .font(Tokens.LightFont.body(12))
        .foregroundStyle(Tokens.Window.textPrimary)
        .lineSpacing(4)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white)
        .overlay(alignment: .topLeading) {
            if focused {
                Rectangle()
                    .fill(Tokens.Window.accent)
                    .frame(width: 1.5, height: 17)
                    .offset(x: 15, y: 15)
            }
        }
    }
}

/// A drafted reply that introduces the writer by name, for the page that asks for it.
///
/// The written text is Japanese in the Chinese interface, per §17: the interface is
/// Chinese and the buttons still write Japanese, so translating the mail body would be
/// showing output the buttons will not produce.
struct OnboardingNameMailBody: View {
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(tr("佐藤さん", "Sam Rivera", "佐藤さん"))
            Text(tr(
                "ご連絡ありがとうございます。",
                "Thank you for your message.",
                "ご連絡ありがとうございます。"
            ))
            introduction
            Text(tr(
                "明日の打ち合わせについて、15時からで承知いたしました。",
                "3pm tomorrow works on my end — see you then.",
                "明日の打ち合わせについて、15時からで承知いたしました。"
            ))
            .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .font(Tokens.LightFont.Onboarding.body)
        .foregroundStyle(Tokens.Window.textPrimary)
        .lineSpacing(4)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white)
    }

    /// One concatenated `Text` rather than an `HStack`: the name lands before the
    /// copula in Japanese and after the verb in English, and only a single `Text` wraps
    /// the sentence correctly whichever side of it is long. An empty half costs nothing
    /// here — unlike `PillSentence`, a concatenation has no spacing to leave behind.
    private var introduction: Text {
        Text(tr("", "I'm ", ""))
            + enteredName
            + Text(tr("です。", ".", "です。"))
    }

    /// Bold, not tinted: §8 keeps indigo for progress, selection and the primary
    /// action, and this is neither — it is the one word on the page that is the user's.
    private var enteredName: Text {
        let entered = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty else {
            return Text(tr("お名前", "your name", "お名前"))
                .foregroundStyle(Tokens.Window.textTertiary)
        }
        return Text(entered).fontWeight(.medium)
    }
}

struct OnboardingOverlayBar: View {
    let labels: [String]
    var expanded = true

    var body: some View {
        HStack(spacing: expanded ? 6 : 0) {
            BrandGlyph(size: 16, animation: expanded ? .engaged : .idle)

            if expanded {
                Rectangle()
                    .fill(Tokens.Overlay.hairline)
                    .frame(width: 1, height: 15)

                ForEach(Array(labels.prefix(4).enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(Tokens.Font.body(10, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                }

                Rectangle()
                    .fill(Tokens.Overlay.hairline)
                    .frame(width: 1, height: 15)
                Icon(.edit, size: 12)
            }
        }
        .foregroundStyle(Tokens.Overlay.textPrimary)
        .padding(.horizontal, expanded ? 12 : 14)
        .frame(height: expanded ? 34 : 28)
        .background(Capsule().fill(Tokens.Overlay.canvas))
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
    }
}

/// The System Settings → Accessibility pane, drawn close to the real window so the
/// step transfers: the pane name in the title bar, a sidebar with the pane selected,
/// the explanation line, and a short app list whose toggles the user will recognise.
/// Only the KeigoButton row reflects real state; the two Apple-app rows are set
/// dressing that keeps the list from looking like it contains one app. Deliberately
/// sparser than the real pane — a dozen sidebar categories and app rows add nothing
/// to the lesson.
struct OnboardingSystemSettingsScene: View {
    let granted: Bool

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            HStack(spacing: 0) {
                sidebar
                content
            }
        }
        .foregroundStyle(Tokens.Window.textPrimary)
        .frame(height: 320)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .padding(24)
        .accessibilityHidden(true)
    }

    private var titleBar: some View {
        ZStack {
            Text(tr("アクセシビリティ", "Accessibility", "辅助功能"))
                .font(Tokens.LightFont.body(12, weight: .semibold))
            HStack(spacing: 16) {
                MockTrafficLights()
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Tokens.Window.textSecondary)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Tokens.Window.textTertiary)
                }
                .font(.system(size: 10, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 34)
        .background(Color(hex: 0xf4f4f6))
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                Text(tr("検索", "Search", "搜索"))
                    .font(Tokens.LightFont.body(11))
            }
            .foregroundStyle(Tokens.Window.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.bottom, 8)

            SettingsSidebarRow(symbol: "wifi", tint: Color(hex: 0x007aff), title: "Wi-Fi")
            SettingsSidebarRow(symbol: "gearshape.fill", tint: Color(hex: 0x8e8e93), title: tr("一般", "General", "通用"))
            SettingsSidebarRow(symbol: "figure.stand", tint: Color(hex: 0x007aff), title: tr("アクセシビリティ", "Accessibility", "辅助功能"), selected: true)
            SettingsSidebarRow(symbol: "circle.lefthalf.filled", tint: Color(hex: 0x3a3a3c), title: tr("外観", "Appearance", "外观"))
            SettingsSidebarRow(symbol: "display", tint: Color(hex: 0x007aff), title: tr("ディスプレイ", "Displays", "显示器"))
            SettingsSidebarRow(symbol: "bell.fill", tint: Color(hex: 0xff3b30), title: tr("通知", "Notifications", "通知"))
            Spacer()
        }
        .padding(10)
        .frame(width: 150)
        .background(Color(hex: 0xe9e7ea))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Tokens.Window.hairline).frame(width: 1)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr(
                "以下のアプリケーションにコンピュータの制御を許可します。",
                "Allow the applications below to control your computer.",
                "允许以下应用程序控制您的电脑。"
            ))
            .font(Tokens.LightFont.body(12))
            .foregroundStyle(Tokens.Window.textSecondary)
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                appRow(name: "Terminal", isOn: true) { terminalIcon }
                Hairline().padding(.leading, 50)
                appRow(name: tr("敬語ボタン", "KeigoButton", "敬語ボタン"), isOn: granted) { AppMark(size: 28) }
                Hairline().padding(.leading, 50)
                appRow(name: "TextEdit", isOn: false) { textEditIcon }
                Hairline()
                HStack(spacing: 0) {
                    Text("+").frame(width: 30)
                    Rectangle().fill(Tokens.Window.hairline).frame(width: 1, height: 14)
                    Text("−").frame(width: 30)
                    Spacer()
                }
                .font(Tokens.LightFont.body(13, weight: .medium))
                .foregroundStyle(Tokens.Window.textSecondary)
                .frame(height: 26)
                .background(Color(hex: 0xf7f7f9))
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Tokens.Window.hairline)
            )

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xf6f6f8))
    }

    private func appRow<Icon: View>(name: String, isOn: Bool, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 10) {
            icon()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            Text(name)
                .font(Tokens.LightFont.body(13))
            Spacer(minLength: 0)
            MockSwitch(isOn: isOn)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private var terminalIcon: some View {
        Color(hex: 0x232326)
            .overlay(
                Text("›_")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            )
    }

    private var textEditIcon: some View {
        Color.white
            .overlay(
                Image(systemName: "pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: 0xff9f0a))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.12))
            )
    }
}

private struct MockWindowChrome: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            MockTrafficLights().accessibilityHidden(true)
            Spacer()
            Text(title)
                .font(Tokens.LightFont.body(10, weight: .medium))
                .foregroundStyle(Tokens.Window.textSecondary)
            Spacer()
            Color.clear.frame(width: 42, height: 1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color(hex: 0xf1f1f2))
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private struct MockTrafficLights: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(hex: 0xff605c)).frame(width: 8, height: 8)
            Circle().fill(Color(hex: 0xffbd44)).frame(width: 8, height: 8)
            Circle().fill(Color(hex: 0x00ca4e)).frame(width: 8, height: 8)
        }
    }
}

private struct MockToolbarButton: View {
    let icon: Icon.Name
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Icon(icon, size: 11)
            Text(title)
                .font(Tokens.LightFont.body(10, weight: .medium))
        }
        .foregroundStyle(Tokens.Window.textTertiary)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct MailHeaderRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundStyle(Tokens.Window.textTertiary)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 48, alignment: .trailing)
            Text(value)
                .foregroundStyle(Tokens.Window.textPrimary)
            Spacer()
        }
        .font(Tokens.LightFont.body(10))
        .padding(.horizontal, 14)
        .frame(height: 27)
        .background(.white)
    }
}

/// One row of the mock System Settings sidebar. The glyphs are SF Symbols rather
/// than Reicon on purpose: this is macOS's own chrome being imitated, not our UI,
/// and the real pane's rows are coloured plates with white system glyphs.
private struct SettingsSidebarRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var selected = false

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white)
                )
            Text(title)
                .font(Tokens.LightFont.body(11, weight: selected ? .medium : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Tokens.Window.textPrimary)
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? .white.opacity(0.85) : .clear)
        )
    }
}

/// macOS's own switch (36×22, system blue), not the app's control: it sits in a
/// replica of System Settings and has to read as the toggle the user is about to flip.
private struct MockSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color(hex: 0x007aff) : Color(hex: 0xd6d6da))
                .frame(width: 34, height: 20)
            Circle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .padding(2)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
    }
}
