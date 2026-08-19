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
            if let version = model.availableUpdateVersion {
                updateNotice(version: version)
            }
            statCard
            if let entitlement = model.entitlement {
                if entitlement.hasWelcomeOffer { welcomeOffer(entitlement) }
                planRow(entitlement)
            }
            if !model.isSignedIn || !model.isTrusted { setupRecovery }
            historySection
        }
    }

    // MARK: - Updates

    /// Sparkle's scheduled check runs quietly; this is its gentle reminder. It uses the
    /// same white card, hairline, tinted icon plate and single indigo action as the rest
    /// of the Willow window, so an update is discoverable without becoming an alert.
    private func updateNotice(version: String) -> some View {
        Card(padding: 16) {
            HStack(spacing: 14) {
                IconPlate(icon: .mark, diameter: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(tr(
                            "新しいバージョンがあります",
                            "A new version is available",
                            "有新版本可用"
                        ))
                            .font(Tokens.Font.body(14, weight: .medium))
                            .foregroundStyle(Tokens.Window.textPrimary)
                        Badge("v\(version)")
                    }
                    Text(tr(
                        "敬語ボタン \(version) にアップデートできます。",
                        "KeigoButton \(version) is ready to install.",
                        "敬語ボタン \(version) 已可安装。"
                    ))
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }

                Spacer(minLength: 16)

                ActionButton(
                    tr("アップデートする", "Update", "更新"),
                    style: .primary,
                    action: model.requestAvailableUpdate
                )
            }
        }
    }

    // MARK: - Welcome offer

    /// The end-of-onboarding offer, still open.
    ///
    /// **This card is what stops the offer page being a trap door.** Someone who
    /// pressed 「あとで」 during first run made a decision about a price, not about a
    /// page, and an offer that vanished with the window it was made in would have been
    /// a deadline of about four seconds. The same price, the same deadline, and the
    /// same server-side row (`desktop.welcome_offers`) back both surfaces, so there is
    /// one offer rather than two that happen to agree.
    ///
    /// It sits **above** the quota row rather than below it: the quota row is the
    /// permanent state of the account and this is temporary, and burying a thing with
    /// an expiry under a thing without one gets the priority backwards.
    ///
    /// It disappears the moment `hasWelcomeOffer` goes false — which is the same
    /// predicate `desktop-checkout` enforces server-side, so the card can never outlive
    /// the discount it advertises.
    private func welcomeOffer(_ entitlement: Entitlement) -> some View {
        let currency = model.billingCurrency
        let annual = PlanPricing.welcomeOffer(.year, in: currency)
        let list = PlanPricing.list(.year, in: currency)
        let remaining = entitlement.welcomeOfferExpiresAt
            .flatMap { PlanPricing.offerRemainingText(until: $0) }

        return Card(padding: 16) {
            HStack(spacing: 14) {
                IconPlate(icon: .mark, diameter: 38)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(tr(
                            "はじめての方限定の価格が残っています",
                            "Your introductory price is still open",
                            "新用户优惠价仍然有效"
                        ))
                            .font(Tokens.Font.body(14, weight: .medium))
                            .foregroundStyle(Tokens.Window.textPrimary)
                        if let remaining { Badge(remaining) }
                    }
                    // 特商法第12条の6 ②対価 again: the discounted period and the price
                    // after it, on the same line, wherever the offer is shown.
                    Text(tr(
                        "Pro の初年度が \(annual.display)（通常 \(list.display)）。以降は自動更新です。",
                        "Pro's first year is \(annual.display) instead of \(list.display), then it renews automatically.",
                        "Pro 首年 \(annual.display)（原价 \(list.display)），之后自动续订。"
                    ))
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                // Opens the プラン pane, not Stripe. The monthly/annual choice is the
                // decision being made and `PlanView` is where both prices sit side by
                // side with the 特商法 items around them — the same reasoning
                // `MainModel.openPlanSettings` already carries for アップグレード.
                ActionButton(tr("この価格を見る", "See this price", "查看此价格"), style: .primary) {
                    model.openPlanSettings()
                }
            }
        }
    }

    // MARK: - Plan and quota

    /// `docs/billing.md` §4.5 makes this a requirement rather than a nicety, and the
    /// finding behind it is unusually clean: the driver of billing support tickets is
    /// **an invisible reset date**, not the cap. GitHub Copilot documents its quota
    /// plainly and still carries a continuous stream of confused threads; Grammarly,
    /// which surfaces 「次回リフィルまであと N 日」 at the block point, does not.
    ///
    /// So the date is on the row, and it is the server's computed date — never a fixed
    /// one. A Pro window resets on the subscription anchor and a free one on the 1st,
    /// so 「毎月1日にリセット」 would be wrong for every paying user.
    ///
    /// It sits below the stat card rather than above it because the stats are what the
    /// app has *done*; this is what is left. It is also the only row on ホーム that
    /// comes from the server, which is why it appears only once a read has succeeded —
    /// `model.entitlement` is nil until then and a placeholder would be a claim.
    private func planRow(_ entitlement: Entitlement) -> some View {
        Card(padding: 16, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Badge(entitlement.plan.displayName)
                Text(tr("\(entitlement.used) / \(entitlement.monthLimit) 回", "\(entitlement.used) / \(entitlement.monthLimit) rewrites", "\(entitlement.used) / \(entitlement.monthLimit) 次"))
                    .font(Tokens.Font.body(14, weight: .medium))
                    .foregroundStyle(Tokens.Window.textPrimary)
                Text({
                    let date = Self.resetFormatter.string(from: entitlement.resetsAt)
                    return tr("\(date)にリセット", "Resets on \(date)", "\(date)重置")
                }())
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textSecondary)

                Spacer(minLength: 16)

                if entitlement.plan == .free {
                    ActionButton(tr("アップグレード", "Upgrade", "升级"), style: .primary) { model.openPlanSettings() }
                } else {
                    ActionButton(tr("お支払い管理", "Manage billing", "付款管理"), style: .secondary, enabled: !model.isOpeningBilling) {
                        model.openBillingPortal()
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tokens.Window.group)
                    Capsule()
                        .fill(entitlement.remaining == 0
                              ? Tokens.Window.textSecondary
                              : Tokens.Window.accent)
                        .frame(width: max(0, geo.size.width * entitlement.fraction))
                }
            }
            .frame(height: 6)

            // §3.4 — `past_due` inside the 14-day grace window is still Pro. Saying so
            // here rather than only in the ⚙︎ modal is the whole reason grace exists:
            // the dominant cause of a failed renewal is an expired card, and a user
            // who never opens settings would otherwise find out by being revoked.
            if entitlement.needsPaymentAttention {
                Text(tr(
                    "お支払いを確認できませんでした。カード情報を更新してください。",
                    "We couldn't take your payment. Please update your card.",
                    "无法完成付款。请更新银行卡信息。"
                ))
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textSecondary)
            } else if entitlement.isCancelScheduled, let end = entitlement.cancelsAt {
                // `cancelsAt`, not `cancelAtPeriodEnd` — the boolean is false on a
                // real Portal cancellation under dahlia, so this row never appeared.
                Text({
                    let date = Self.resetFormatter.string(from: end)
                    return tr(
                        "解約手続き済みです。\(date)まで Pro をご利用いただけます。",
                        "Your subscription is cancelled. Pro stays active until \(date).",
                        "已办理取消。Pro 可使用至\(date)。"
                    )
                }())
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textSecondary)
            }
        }
    }

    private static var resetFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageState.current.locale
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = tr("M月d日", "MMMM d", "M月d日")
        return formatter
    }

    // MARK: - How to use it

    /// `design.md` opens its home page with the gesture that runs the product —
    /// "Hold F1 to dictate on ⟨apps⟩" — rather than with the page's name. Ours says
    /// the same thing about hovering, and the icons beside it are the apps this Mac
    /// has actually rewritten in.
    /// Japanese wraps the bar mid-sentence — 「画面の下の ⟨bar⟩ にカーソルを合わせると」 —
    /// and English cannot, so the leading half is allowed to be empty and is then not
    /// laid out at all. An empty `Text` would still take the HStack's spacing.
    private var hoverSentenceBefore: String {
        tr("画面の下の", "", "画面下方的")
    }

    private var hoverSentenceAfter: String {
        tr(
            "にカーソルを合わせると、ボタンが開きます",
            " at the bottom of your screen opens your buttons on hover",
            "，光标悬停即可展开按钮"
        )
    }

    private var usageRow: some View {
        HStack(spacing: 10) {
            if !hoverSentenceBefore.isEmpty {
                Text(hoverSentenceBefore)
                    .font(Tokens.Font.body(15))
                    .foregroundStyle(Tokens.Window.textSecondary)
            }
            PillPreview()
            Text(hoverSentenceAfter)
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
            HStack(alignment: .top, spacing: 0) {
                StatCell(
                    label: tr("今週の書き換え", "This week", "本周改写"),
                    value: Self.number(model.stats.rewritesThisWeek),
                    unit: tr("回", "rewrites", "次")
                )
                StatDivider()
                StatCell(
                    label: tr("累計", "All time", "累计"),
                    value: Self.number(model.stats.totalRewrites),
                    unit: tr("回", "rewrites", "次")
                )
                StatDivider()
                StatCell(
                    label: tr("書き換えた文字数", "Characters", "改写字数"),
                    value: Self.number(model.stats.charactersRewritten),
                    unit: tr("字", "chars", "字")
                )
                StatDivider()
                StatCell(
                    label: tr("連続利用", "Streak", "连续使用"),
                    value: Self.number(model.stats.dayStreak),
                    unit: tr("日", "days", "天")
                )
            }
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Tokens.Window.canvas
                    Image("StatsBackdrop")
                        .resizable()
                        .scaledToFill()
                        // The raster supplies atmosphere, not a coloured card. At
                        // full strength even this pale source read as a gradient.
                        .opacity(0.55)
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: Tokens.Window.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Window.cardRadius, style: .continuous)
                    .strokeBorder(Tokens.Window.hairline, lineWidth: 1)
            )

            if let bundleId = model.stats.topAppBundleId {
                Text({
                    let app = MainModel.appName(for: bundleId)
                    let count = model.stats.topAppCount
                    return tr(
                        "よく使うアプリ: \(app)（\(count)回）",
                        "Most used in \(app) (\(count) rewrites)",
                        "最常用的应用：\(app)（\(count)次）"
                    )
                }())
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textTertiary)
            } else {
                Text(tr(
                    "この Mac に保存された記録から集計しています。",
                    "Counted from the history stored on this Mac.",
                    "根据本机保存的记录统计。"
                ))
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
                    Text(model.isSignedIn
                        ? tr("アクセシビリティを確認してください", "Check Accessibility access", "请检查辅助功能权限")
                        : tr("サインインが必要です", "You need to sign in", "需要登录"))
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(model.isSignedIn
                         ? tr(
                            "編集中の文章を読み書きするための許可が外れています。",
                            "Permission to read and replace the text you are editing has been revoked.",
                            "读写当前编辑文字的权限已被取消。"
                         )
                         : tr(
                            "ボタンを同期して書き換えるには、共有アカウントへ接続します。",
                            "Connect your account to sync your buttons and start rewriting.",
                            "连接共享账户后即可同步按钮并开始改写。"
                         ))
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }
                Spacer()
                ActionButton(model.isSignedIn ? tr("許可する", "Grant access", "授予权限") : tr("サインイン", "Sign in", "登录"), style: .primary) {
                    if model.isSignedIn { model.requestAccessibility() } else { model.page = .account }
                }
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: tr("履歴", "History", "历史")) {
                if !model.history.isEmpty {
                    SearchField(
                        placeholder: tr("\(model.history.count)件を検索", "Search \(model.history.count) rewrites", "搜索\(model.history.count)条记录"),
                        text: $model.historySearch,
                        width: 220
                    )
                }
            }

            if !model.historyEnabled {
                emptyCard(
                    icon: .history,
                    text: tr("履歴の保存はオフになっています。", "History is turned off.", "历史保存已关闭。"),
                    action: (
                        tr("環境設定を開く", "Open Settings", "打开偏好设置"),
                        { model.showsPreferences = true }
                    )
                )
            } else if model.history.isEmpty {
                emptyCard(
                    icon: .noteAdd,
                    text: tr(
                        "まだ履歴がありません。バーのボタンを押すとここに残ります。",
                        "Nothing here yet. Press a button on the bar and it will show up.",
                        "还没有记录。按下工具栏上的按钮后就会出现在这里。"
                    ),
                    action: nil
                )
            } else if model.filteredHistory.isEmpty {
                emptyCard(icon: .search, text: tr("該当する履歴がありません。", "No rewrites match that.", "没有匹配的记录。"), action: nil)
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
        if calendar.isDateInToday(day) { return tr("今日", "Today", "今天") }
        if calendar.isDateInYesterday(day) { return tr("昨日", "Yesterday", "昨天") }
        return dayFormatter.string(from: day)
    }

    private static var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageState.current.locale
        formatter.setLocalizedDateFormatFromTemplate("Md")
        return formatter
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
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Willow's stat card is one object with four columns. A quiet internal rule keeps
/// the values scannable without turning them into four separate tiles.
private struct StatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.Window.hairline.opacity(0.9))
            .frame(width: 1, height: 48)
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
                        Text(tr("挿入済み", "Inserted", "已插入"))
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

                // A rewrite written from nothing has no original (§18), and a 元の文章
                // heading over an empty line reads as text that failed to load.
                if isExpanded, !entry.originalText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("元の文章", "Original", "原文"))
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

            IconButton(icon: .copy, help: tr("コピー", "Copy", "复制"), action: onCopy)
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
