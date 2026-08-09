import SwiftUI

struct OnboardingVisualStage<Content: View>: View {
    var cornerRadius: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            OnboardingLavenderBackground()
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06))
        )
    }
}

private struct OnboardingLavenderBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: 0xefecfa),
                        Color(hex: 0xddd8f2),
                        Color(hex: 0xc8c1e8),
                    ],
                    startPoint: UnitPoint(x: 0.08, y: 0),
                    endPoint: UnitPoint(x: 0.92, y: 1)
                )
                RadialGradient(
                    colors: [.white, .white.opacity(0)],
                    center: UnitPoint(x: 0.18, y: 0.12),
                    startRadius: 0,
                    endRadius: diagonal * 0.62
                )
                RadialGradient(
                    colors: [Color(hex: 0xa99ed4), Color(hex: 0xa99ed4).opacity(0)],
                    center: UnitPoint(x: 0.88, y: 0.84),
                    startRadius: 0,
                    endRadius: diagonal * 0.56
                )
                .opacity(0.78)
            }
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
            let horizontalInset = max(18, proxy.size.width * 0.055)
            let bottomInset = showsBar ? max(44, proxy.size.height * 0.16) : 22

            ZStack(alignment: .bottom) {
                OnboardingMailWindow(editor: editor)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, max(18, proxy.size.height * 0.07))
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
            MockWindowChrome(title: "メール — 新規メッセージ")

            HStack(spacing: 14) {
                MockToolbarButton(icon: .edit, title: "送信")
                MockToolbarButton(icon: .copy, title: "下書き")
                Spacer()
                Icon(.close, size: 12)
                    .foregroundStyle(Tokens.Window.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Color(hex: 0xf8f8f9))

            MailHeaderRow(label: "宛先", value: "佐藤さん")
            Hairline()
            MailHeaderRow(label: "件名", value: "明日の打ち合わせについて")
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
        GeometryReader { proxy in
            VStack(spacing: 0) {
                MockWindowChrome(title: "Slack — Core7")

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: 0x4a154b))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text("C")
                                        .font(Tokens.Font.body(13, weight: .medium))
                                        .foregroundStyle(.white)
                                )
                            Text("Core7")
                                .font(Tokens.Font.body(13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 48)

                        SlackSidebarRow(title: "スレッド")
                        SlackSidebarRow(title: "メンション")

                        Text("チャンネル")
                            .font(Tokens.Font.body(10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.horizontal, 14)
                            .padding(.top, 18)
                            .padding(.bottom, 5)

                        SlackSidebarRow(title: "#  general")
                        SlackSidebarRow(title: "#  product", selected: true)
                        SlackSidebarRow(title: "#  random")
                        Spacer()
                    }
                    .frame(width: max(142, proxy.size.width * 0.22), alignment: .topLeading)
                    .background(Color(hex: 0x3f0e40))

                    VStack(spacing: 0) {
                        HStack(spacing: 9) {
                            Text("# product")
                                .font(Tokens.Font.body(14, weight: .medium))
                                .foregroundStyle(Tokens.Window.textPrimary)
                            Text("8人")
                                .font(Tokens.Font.body(10))
                                .foregroundStyle(Tokens.Window.textTertiary)
                            Spacer()
                            Icon(.search, size: 13)
                                .foregroundStyle(Tokens.Window.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 45)
                        .background(.white)
                        .overlay(alignment: .bottom) { Hairline() }

                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color(hex: 0xd8d1ed))
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Text("AM")
                                            .font(Tokens.Font.body(10, weight: .medium))
                                            .foregroundStyle(Color(hex: 0x4a154b))
                                    )

                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 7) {
                                        Text("Aki Matsuda")
                                            .font(Tokens.Font.body(12, weight: .medium))
                                        Text("10:24")
                                            .font(Tokens.Font.body(9))
                                            .foregroundStyle(Tokens.Window.textTertiary)
                                    }
                                    Text(message)
                                        .font(Tokens.Font.body(13))
                                        .foregroundStyle(Tokens.Window.textPrimary)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Button(action: onCopy) {
                                        HStack(spacing: 6) {
                                            Icon(copied ? .check : .copy, size: 12)
                                            Text(copied ? "コピーしました" : "メッセージをコピー")
                                                .font(Tokens.Font.body(11, weight: .medium))
                                        }
                                        .foregroundStyle(
                                            copied ? Tokens.Window.success : Tokens.Window.accentText
                                        )
                                        .padding(.horizontal, 9)
                                        .frame(height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7)
                                                .fill(copied ? Tokens.Window.surface : Tokens.Window.accentTint)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .cursor(.pointingHand)
                                    .padding(.top, 3)
                                }
                            }
                            .padding(18)

                            Spacer(minLength: 12)

                            VStack(alignment: .leading, spacing: 7) {
                                Text(copied ? "返信先を選択済み" : "コピーすると返信モードになります")
                                    .font(Tokens.Font.body(10, weight: .medium))
                                    .foregroundStyle(
                                        copied ? Tokens.Window.success : Tokens.Window.textTertiary
                                    )
                                composer()
                                    .frame(height: 76)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9)
                                            .strokeBorder(
                                                copied ? Tokens.Window.accent : Tokens.Window.hairline,
                                                lineWidth: copied ? 1.5 : 1
                                            )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .padding(14)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.white)
                    }
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.09))
            )
            .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            .padding(.horizontal, max(26, proxy.size.width * 0.055))
            .padding(.vertical, max(20, proxy.size.height * 0.06))
        }
    }
}

private struct SlackSidebarRow: View {
    let title: String
    var selected = false

    var body: some View {
        Text(title)
            .font(Tokens.Font.body(11, weight: selected ? .medium : .regular))
            .foregroundStyle(.white.opacity(selected ? 1 : 0.72))
            .padding(.horizontal, 14)
            .frame(height: 27)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color(hex: 0x1164a3) : .clear)
    }
}

struct OnboardingStaticMailBody: View {
    let text: String
    var focused = true

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("佐藤さん")
            Text(text)
            Text("よろしくお願いします。")
            Spacer(minLength: 0)
        }
        .font(Tokens.Font.body(12))
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

struct OnboardingSystemSettingsScene: View {
    let granted: Bool

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    MockTrafficLights()
                        .padding(.bottom, 15)

                    HStack(spacing: 7) {
                        Icon(.search, size: 12)
                        Text("検索")
                            .font(Tokens.Font.body(11))
                    }
                    .foregroundStyle(Tokens.Window.textTertiary)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.72)))

                    SettingsSidebarRow(icon: .settings, title: "一般")
                        .padding(.top, 12)
                    SettingsSidebarRow(icon: .user, title: "ユーザとグループ")
                    SettingsSidebarRow(icon: .accessibility, title: "プライバシーとセキュリティ", selected: true)
                    SettingsSidebarRow(icon: .info, title: "このMacについて")
                    Spacer()
                }
                .padding(14)
                .frame(width: max(145, proxy.size.width * 0.34), alignment: .topLeading)
                .background(.white.opacity(0.52))

                Rectangle()
                    .fill(Color.black.opacity(0.07))
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: 0) {
                    Text("アクセシビリティ")
                        .font(Tokens.Font.display(17))
                        .foregroundStyle(Tokens.Window.textPrimary)

                    Text("以下のアプリケーションに、Macの操作を許可します。")
                        .font(Tokens.Font.body(11))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .padding(.top, 7)

                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white)
                                .frame(width: 34, height: 34)
                                .overlay(AppMark(size: 20))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.Window.hairline))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("敬語ボタン")
                                    .font(Tokens.Font.body(12, weight: .medium))
                                Text("ほかのアプリの入力欄を読み書き")
                                    .font(Tokens.Font.body(10))
                                    .foregroundStyle(Tokens.Window.textSecondary)
                            }
                            Spacer(minLength: 8)
                            MockSwitch(isOn: granted)
                        }
                        .padding(12)

                        Hairline()

                        HStack(spacing: 6) {
                            Icon(.add, size: 12)
                            Icon(.close, size: 12)
                            Spacer()
                            Text(granted ? "許可済み" : "許可が必要です")
                                .font(Tokens.Font.body(10, weight: .medium))
                                .foregroundStyle(granted ? Tokens.Window.success : Tokens.Window.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.82)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.08)))
                    .padding(.top, 18)

                    HStack(alignment: .top, spacing: 8) {
                        Icon(.info, size: 12)
                            .opticalCentre()
                        Text("マイクや画面収録へのアクセスは必要ありません。")
                            .font(Tokens.Font.body(10))
                    }
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .padding(.top, 14)
                    Spacer()
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(hex: 0xf7f7f8).opacity(0.9))
            }
            .background(.white.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.black.opacity(0.09)))
            .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            .padding(24)
        }
    }
}

private struct MockWindowChrome: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            MockTrafficLights()
            Spacer()
            Text(title)
                .font(Tokens.Font.body(10, weight: .medium))
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
                .font(Tokens.Font.body(10, weight: .medium))
        }
        .foregroundStyle(Tokens.Window.textSecondary)
    }
}

private struct MailHeaderRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundStyle(Tokens.Window.textTertiary)
                .frame(width: 32, alignment: .trailing)
            Text(value)
                .foregroundStyle(Tokens.Window.textPrimary)
            Spacer()
        }
        .font(Tokens.Font.body(10))
        .padding(.horizontal, 14)
        .frame(height: 27)
        .background(.white)
    }
}

private struct SettingsSidebarRow: View {
    let icon: Icon.Name
    let title: String
    var selected = false

    var body: some View {
        HStack(spacing: 7) {
            Icon(icon, size: 12)
                .opticalCentre()
            Text(title)
                .font(Tokens.Font.body(10, weight: selected ? .medium : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(Tokens.Window.textPrimary)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Tokens.Window.rowActive.opacity(0.92) : .clear)
        )
    }
}

private struct MockSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Tokens.Window.accent : Tokens.Window.controlOff)
                .frame(width: 32, height: 19)
            Circle()
                .fill(.white)
                .frame(width: 15, height: 15)
                .padding(2)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        }
    }
}
