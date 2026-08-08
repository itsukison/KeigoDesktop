import DesktopRewriteKit
import SwiftUI

/// ホーム — what the app has done for you, and nothing it has not.
///
/// Structurally `design.md`'s home page: a one-line **how to use it** row instead of a
/// page title, a single four-column stat card, the setup checklist as a horizontal row
/// of numbered task cards, then the history under a search field. The one place it
/// diverges is the headline number — the reference's is "time saved", derived from
/// dictated words over typing speed. A rewrite tool has no such ground truth, so all
/// four numbers here are directly counted (see `RewriteStats`).
struct HomeView: View {
    @ObservedObject var model: MainModel

    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            usageRow
            statCard
            if !model.isSignedIn || !model.isTrusted { setupRecovery }
            historySection
        }
    }

    // MARK: - How to use it

    /// `design.md` opens its home page with the gesture that runs the product —
    /// "Hold F1 to dictate on ⟨apps⟩" — rather than with the page's name. Ours says
    /// the same thing about hovering, and the icons beside it are the apps this Mac
    /// has actually rewritten in.
    private var usageRow: some View {
        HStack(spacing: 10) {
            Text("画面の下の")
                .font(Tokens.Font.body(15))
                .foregroundStyle(Tokens.Window.textSecondary)
            BarPreview()
            Text("にカーソルを合わせると、ボタンが開きます")
                .font(Tokens.Font.body(15))
                .foregroundStyle(Tokens.Window.textSecondary)

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                ForEach(recentApps, id: \.self) { bundleId in
                    AppIconView(bundleId: bundleId, size: 22)
                }
            }
        }
    }

    /// Most recent first, deduplicated — the apps the user is working in now, not the
    /// ones they used most six months ago.
    private var recentApps: [String] {
        var seen: [String] = []
        for entry in model.history {
            guard let bundleId = entry.hostAppBundleId, !seen.contains(bundleId) else { continue }
            seen.append(bundleId)
            if seen.count == 4 { break }
        }
        return seen
    }

    // MARK: - Stats

    private var statCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Card(padding: 24) {
                HStack(alignment: .top, spacing: 0) {
                    StatCell(
                        label: "今週の書き換え",
                        value: Self.number(model.stats.rewritesThisWeek),
                        unit: "回"
                    )
                    StatCell(
                        label: "累計",
                        value: Self.number(model.stats.totalRewrites),
                        unit: "回"
                    )
                    StatCell(
                        label: "書き換えた文字数",
                        value: Self.number(model.stats.charactersRewritten),
                        unit: "字"
                    )
                    StatCell(
                        label: "連続利用",
                        value: Self.number(model.stats.dayStreak),
                        unit: "日"
                    )
                }
            }

            if let bundleId = model.stats.topAppBundleId {
                Text("よく使うアプリ: \(MainModel.appName(for: bundleId))（\(model.stats.topAppCount)回）")
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textTertiary)
            } else {
                Text("この Mac に保存された記録から集計しています。")
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textTertiary)
            }
        }
    }

    // MARK: - Setup recovery

    private var setupRecovery: some View {
        Card(padding: 16) {
            HStack(spacing: 14) {
                IconPlate(
                    icon: model.isSignedIn ? .accessibility : .profile,
                    diameter: 38
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isSignedIn ? "アクセシビリティを確認してください" : "サインインが必要です")
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(model.isSignedIn
                         ? "編集中の文章を読み書きするための許可が外れています。"
                         : "ボタンを同期して書き換えるには、共有アカウントへ接続します。")
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }
                Spacer()
                ActionButton(model.isSignedIn ? "許可する" : "サインイン", style: .primary) {
                    if model.isSignedIn { model.requestAccessibility() } else { model.page = .account }
                }
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "履歴") {
                if !model.history.isEmpty {
                    SearchField(
                        placeholder: "\(model.history.count)件を検索",
                        text: $model.historySearch,
                        width: 220
                    )
                }
            }

            if !model.historyEnabled {
                emptyCard(
                    icon: .history,
                    text: "履歴の保存はオフになっています。",
                    action: ("環境設定を開く", { model.showsPreferences = true })
                )
            } else if model.history.isEmpty {
                emptyCard(
                    icon: .noteAdd,
                    text: "まだ履歴がありません。バーのボタンを押すとここに残ります。",
                    action: nil
                )
            } else if model.filteredHistory.isEmpty {
                emptyCard(icon: .search, text: "該当する履歴がありません。", action: nil)
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(groups, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionCaption(text: Self.dayLabel(group.key))
                            RowGroup {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) {
                                    index, entry in
                                    if index > 0 { Hairline() }
                                    HistoryRow(
                                        entry: entry,
                                        isExpanded: expanded == entry.id,
                                        onToggle: {
                                            expanded = expanded == entry.id ? nil : entry.id
                                        },
                                        onCopy: { model.copy(entry) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func emptyCard(
        icon: Icon.Name,
        text: String,
        action: (String, () -> Void)?
    ) -> some View {
        Card(padding: 20) {
            HStack(spacing: 14) {
                IconPlate(icon: icon, diameter: 36)
                Text(text)
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
                Spacer(minLength: 12)
                if let action {
                    ActionButton(action.0, style: .secondary, action: action.1)
                }
            }
        }
    }

    private var groups: [(key: Date, entries: [RewriteHistoryEntry])] {
        let calendar = Calendar.current
        return Dictionary(grouping: model.filteredHistory) {
            calendar.startOfDay(for: $0.createdAt)
        }
        .sorted { $0.key > $1.key }
        .map { (key: $0.key, entries: $0.value) }
    }

    // MARK: - Formatting

    private static func number(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今日" }
        if calendar.isDateInYesterday(day) { return "昨日" }
        return dayFormatter.string(from: day)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
    }()
}

/// The bar itself, in the usage row — not a label naming it, the real thing.
///
/// This used to be `Chip("バー")`, a plain accent-tinted word. Saying "hover the bar"
/// without showing it made the reader build their own mental picture of a shape that
/// looks nothing like the actual dark pill; this is `PillRootView`'s `.pill` state,
/// same constants, same mark, so what is described is what is seen.
private struct BarPreview: View {
    var body: some View {
        BrandMark()
            .padding(.horizontal, (Tokens.Geometry.pillCollapsedWidth - 16) / 2)
            .frame(height: Tokens.Geometry.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Overlay.pillRadius, style: .continuous)
                    .fill(Tokens.Overlay.canvas)
            )
            .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
    }
}

/// Label above, number below. The number is semibold — the reference's stat row reads
/// as data because the figures are the heaviest type on the page, which is the exact
/// opposite of the whisper-weight display face this window used to set them in.
private struct StatCell: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Tokens.Font.body(13))
                .foregroundStyle(Tokens.Window.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Tokens.Font.display(26))
                    .tracking(Tokens.Font.displayTracking(26))
                    .foregroundStyle(Tokens.Window.textPrimary)
                Text(unit)
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryRow: View {
    let entry: RewriteHistoryEntry
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // A monospaced timestamp keeps the left edge of the list straight — the
            // reference's history does the same, and it is `design.md`'s one
            // technical-metadata face.
            Text(Self.timeFormatter.string(from: entry.createdAt))
                .font(Tokens.Font.mono(12))
                .foregroundStyle(Tokens.Window.textTertiary)
                .frame(width: 46, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Badge(entry.label)
                    if let bundleId = entry.hostAppBundleId {
                        Text(MainModel.appName(for: bundleId))
                            .font(Tokens.Font.body(12))
                            .foregroundStyle(Tokens.Window.textTertiary)
                    }
                    if entry.accepted {
                        Text("挿入済み")
                            .font(Tokens.Font.body(11))
                            .foregroundStyle(Tokens.Window.textTertiary)
                    }
                }

                Text(entry.rewrittenText)
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .lineSpacing(5)
                    .lineLimit(isExpanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("元の文章")
                            .font(Tokens.Font.body(11))
                            .foregroundStyle(Tokens.Window.textTertiary)
                        Text(entry.originalText)
                            .font(Tokens.Font.body(13))
                            .foregroundStyle(Tokens.Window.textSecondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            IconButton(icon: .copy, help: "コピー", action: onCopy)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // The row expands on click, so it has to look clickable. Without the fill the
        // only hover feedback was the copy button fading in at the far right.
        .background(hovering ? Tokens.Window.surface : Tokens.Window.canvas)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
