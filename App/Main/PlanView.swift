import DesktopRewriteKit
import SwiftUI

/// The プラン pane of the ⚙︎ modal.
///
/// Structure is `reference/prcing.png`'s: an interval toggle centred above a row of
/// plan cards, each a feature checklist under a price, with the current plan's action
/// inert and the other's live; then the period's usage below. Three deliberate
/// departures from that image:
///
/// - **Two cards, not four.** `docs/pricing.md` §1 has no third tier and no
///   Enterprise: volume is the only differentiation axis available, and a tier is
///   added when Pro contains something worth segmenting on. Drawing Business and
///   Enterprise plates we cannot sell would be the "empty destinations" mistake
///   `AGENTS.md` §14 already rejected once.
/// - **「2ヶ月分お得」 rather than a percentage.** ¥14,400 against ¥1,480 × 12 saves
///   ¥3,360 — 2.27 months; $120 against $12 × 12 saves exactly two. §4 sells the
///   annual plan on the ¥1,200 / $10 月相当 figure so the buyer compares it against
///   ¥1,480 / $12 in one step with no arithmetic; a 「Save 20%」 badge asks them to do
///   the multiplication instead. The badge is **computed** (`PlanPricing.monthsFree`)
///   rather than written, because a hard-coded 2 beside a changed price is how this
///   claim would quietly stop being true.
/// - **The usage row is this period's, not "this week".** And it carries the computed
///   reset date, which §4.5 makes a requirement rather than a nicety: a Pro window
///   resets on the subscription anchor and a free one on the 1st, so there is no
///   fixed date that is true for both.
struct PlanView: View {
    @ObservedObject var model: MainModel

    /// Defaults to annual, per §4 — annual prepay converts cash flow forward and
    /// removes eleven monthly churn decisions.
    @State private var interval: Entitlement.Interval = .year

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.isSignedIn {
                intervalToggle
                cards
                if let entitlement = model.entitlement {
                    usage(entitlement)
                    footnotes(entitlement)
                }
            } else {
                signedOutNotice
            }

            if let error = model.entitlementError {
                Text(error)
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textTertiary)
            }
        }
        .task { await model.reloadEntitlement() }
    }

    private var plan: Entitlement.Plan { model.entitlement?.plan ?? .free }

    /// A live subscription's currency outranks the interface language — see
    /// `MainModel.billingCurrency`. Read once per body so every amount on the page
    /// is denominated the same way, including the mixed case where a yen subscriber
    /// is reading the English interface.
    private var currency: BillingCurrency { model.billingCurrency }

    /// Whether this page should quote the welcome price rather than the list price.
    /// The server decides whether the discount is actually applied at checkout; this
    /// only decides what the card says, and the two are kept in step by both reading
    /// the same `welcome_offer_expires_at`.
    private var offerIsLive: Bool { model.entitlement?.hasWelcomeOffer ?? false }

    // MARK: - Interval

    private var intervalToggle: some View {
        let months = PlanPricing.monthsFree(in: currency)
        return HStack(spacing: 0) {
            segment(
                .year,
                title: tr("年払い", "Yearly", "年付"),
                badge: tr("\(months)ヶ月分お得", "\(months) months free", "省\(months)个月")
            )
            segment(.month, title: tr("月払い", "Monthly", "月付"), badge: nil)
        }
        .padding(3)
        .background(Capsule().fill(Tokens.Window.group))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func segment(_ value: Entitlement.Interval, title: String, badge: String?) -> some View {
        let isOn = interval == value
        return Button { interval = value } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(Tokens.Font.body(13, weight: isOn ? .medium : .regular))
                if let badge {
                    Text(badge)
                        .font(Tokens.Font.body(11, weight: .medium))
                        .foregroundStyle(Tokens.Window.accentText)
                }
            }
            .foregroundStyle(isOn ? Tokens.Window.textPrimary : Tokens.Window.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                Capsule().fill(isOn ? Tokens.Window.canvas : .clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    // MARK: - Cards

    private var cards: some View {
        HStack(alignment: .top, spacing: 14) {
            PlanCard(
                name: tr("無料", "Free", "免费"),
                price: PlanPricing.Amount(0, currency).display,
                unit: tr("/ 月", "/ month", "/ 月"),
                caption: nil,
                features: [
                    tr("月50回まで書き換え", "50 rewrites a month", "每月50次改写"),
                    tr("自分のボタンをそのまま同期", "Your own buttons, synced", "同步你自己的按钮"),
                    tr("どのアプリでも使える", "Works in every app", "在任何应用中都能使用"),
                ],
                highlighted: false,
                action: plan == .free
                    ? .current
                    : .none
            )

            PlanCard(
                name: "Pro",
                price: proPrice.display,
                unit: proUnit,
                flag: offerFlag,
                // **Not 「税込」.** Core7 is a 免税事業者 and not an 適格請求書発行事業者
                // (`docs/billing.md` §10), so a 消費税 claim is one we are not in a
                // position to make. 消費税法第63条's 総額表示義務 explicitly excludes
                // 免税事業者, so nothing requires the word either — what the buyer
                // needs is the amount that will actually be charged, which is what
                // this says. 自動更新 stays because 特商法第12条の6 ①分量 requires it,
                // and while an offer is live the same article's ②対価 is why the
                // caption names the price it renews at rather than only the discount.
                caption: proCaption,
                features: [
                    tr("月1,000回まで書き換え", "1,000 rewrites a month", "每月1,000次改写"),
                    tr("通常のご利用では到達しません", "More than normal use reaches", "正常使用不会达到上限"),
                    tr("いつでもワンクリックで解約", "Cancel any time, in one click", "随时一键取消"),
                ],
                highlighted: true,
                action: proAction
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - What the Pro card says

    /// The headline figure.
    ///
    /// Annual is quoted **per month** at list price so the buyer compares ¥1,200
    /// against ¥1,480 (or $10 against $12) in one step — §4's whole argument for the
    /// annual amount being divisible by twelve. While the welcome offer is live the
    /// annual card switches to the **total**: ¥9,600 ÷ 12 is ¥800, but $80 ÷ 12 is
    /// $6.66…, and `monthlyEquivalent` returns nil rather than inventing that
    /// precision. Quoting one currency per month and the other per year would make
    /// the same card mean two different things.
    private var proPrice: PlanPricing.Amount {
        if offerIsLive { return PlanPricing.welcomeOffer(interval, in: currency) }
        if interval == .year, let monthly = PlanPricing.monthlyEquivalent(ofYearly: currency) {
            return monthly
        }
        return PlanPricing.list(interval, in: currency)
    }

    private var proUnit: String {
        switch (interval, offerIsLive) {
        case (.year, true):
            return tr("/ 初年度", "for the first year", "首年")
        case (.year, false):
            return tr("/ 月相当", "/ month, billed yearly", "/ 月（按年计费）")
        case (.month, true):
            return tr(
                "/ 月（最初の\(PlanPricing.welcomeOfferMonthlyPeriods)ヶ月）",
                "/ month for \(PlanPricing.welcomeOfferMonthlyPeriods) months",
                "/ 月（前\(PlanPricing.welcomeOfferMonthlyPeriods)个月）"
            )
        case (.month, false):
            return tr("/ 月", "/ month", "/ 月")
        }
    }

    /// 特商法第12条の6 ①分量・②対価. Without an offer this states the amount and that it
    /// renews; with one it must *also* state what it renews **at**, because a price
    /// that changes after the first period is the disclosure the article exists for.
    private var proCaption: String {
        let list = PlanPricing.list(interval, in: currency).display
        guard offerIsLive else {
            return interval == .year
                ? tr(
                    "年 \(list) を一括・自動更新",
                    "\(list) once a year, renews automatically",
                    "每年一次性支付 \(list)，自动续订"
                )
                : tr(
                    "毎月 \(list) を自動更新",
                    "\(list) every month, renews automatically",
                    "每月 \(list)，自动续订"
                )
        }

        let offer = PlanPricing.welcomeOffer(interval, in: currency).display
        let months = PlanPricing.welcomeOfferMonthlyPeriods
        return interval == .year
            ? tr(
                "初年度 \(offer)、2年目以降は年 \(list) を自動更新",
                "\(offer) for the first year, then \(list) a year, renews automatically",
                "首年 \(offer)，第二年起每年 \(list)，自动续订"
            )
            : tr(
                "最初の\(months)ヶ月は月 \(offer)、以降は月 \(list) を自動更新",
                "\(offer) a month for \(months) months, then \(list) a month, renews automatically",
                "前\(months)个月每月 \(offer)，之后每月 \(list)，自动续订"
            )
    }

    /// The deadline, stated on the card rather than only on the onboarding page the
    /// offer was made on. An offer whose expiry is invisible is one the user can only
    /// discover by losing it.
    private var offerFlag: String? {
        guard offerIsLive, let expiry = model.entitlement?.welcomeOfferExpiresAt else { return nil }
        guard let remaining = PlanPricing.offerRemainingText(until: expiry) else { return nil }
        return tr("はじめての方限定 · \(remaining)", "New customers · \(remaining)", "新用户限定 · \(remaining)")
    }

    private var proAction: PlanCard.Action {
        if plan == .pro {
            if model.entitlement?.interval == interval { return .current }
            // Same tier, different interval: still an upgrade path, and §9 row 11's
            // rule is that we refuse it while a cancellation or schedule is pending
            // rather than reason about Stripe's interaction matrix. The server
            // enforces that; the button just stops being an obvious no-op.
            if model.entitlement?.isCancelScheduled == true { return .current }
            return .change(
                title: interval == .year
                    ? tr("年払いに変更", "Switch to yearly", "改为年付")
                    : tr("月払いに変更", "Switch to monthly", "改为月付"),
                busy: model.isOpeningBilling,
                // Changing interval on a LIVE subscription is a portal operation, not
                // a purchase. `beginCheckout` would only hand back a portal URL here
                // anyway — `desktop-checkout`'s pre-flight (d) refuses to open a
                // second Checkout for someone who already has a subscription — but it
                // returns the OVERVIEW, leaving the user to find the plan switch
                // themselves. Asking for the update screen directly is the same
                // decision made one step earlier.
                run: { model.openBillingPortal(.update) }
            )
        }
        return .change(
            title: tr("アップグレード", "Upgrade", "升级"),
            busy: model.isOpeningBilling,
            run: { model.beginCheckout(interval == .year ? .yearly : .monthly) }
        )
    }

    // MARK: - Usage

    /// §3's requirement, and the one row that has to be here whatever else is:
    /// a quota the user cannot see is a quota that ambushes them.
    private func usage(_ entitlement: Entitlement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: tr("今月の書き換え", "This month", "本月改写"))
            Card(padding: 16, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(entitlement.used) / \(entitlement.monthLimit)")
                        .font(Tokens.Font.display(20))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(tr("回", "rewrites", "次"))
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                    Spacer()
                    Text({
                        let date = Self.resetFormatter.string(from: entitlement.resetsAt)
                        return tr("\(date)にリセット", "Resets \(date)", "\(date)重置")
                    }())
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
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
            }
        }
    }

    /// The 管理 block: what state the subscription is in, and every action available
    /// from it — each as its own labelled button.
    ///
    /// This used to be a single 「お支払い管理」 that dropped the user on the portal's
    /// overview. Cancelling, switching to annual and un-cancelling were all reachable,
    /// but only by hunting for them once the browser opened, which reads exactly like
    /// they are not offered at all. Naming each action and deep-linking it (§3 of
    /// `desktop-portal`) is the difference between "available" and "findable".
    ///
    /// The three states are mutually exclusive and ordered by urgency: a failed
    /// payment is the only one with a deadline attached, so it outranks a scheduled
    /// cancellation, which in turn replaces the everyday row.
    @ViewBuilder
    private func footnotes(_ entitlement: Entitlement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // §3.4 — `past_due` inside the grace window is still Pro, and the banner
            // is the whole point of granting grace instead of revoking on failure.
            if entitlement.needsPaymentAttention {
                noticeRow(
                    tr(
                        "お支払いを確認できませんでした。カード情報を更新してください。",
                        "We couldn't take your payment. Please update your card.",
                        "无法完成付款。请更新银行卡信息。"
                    ),
                    actions: [(tr("お支払い方法を更新", "Update payment method", "更新付款方式"), .paymentMethod)]
                )
            } else if entitlement.isCancelScheduled, let end = entitlement.cancelsAt {
                // **`cancelsAt`, not `cancelAtPeriodEnd`.** The old branch tested the
                // boolean, which a real Portal cancellation on dahlia never sets — so
                // this notice silently never appeared and the user was left with no
                // idea how long they still had. See `Entitlement.cancelsAt`.
                //
                // Accurate and reassuring, and §10 pairs it with the 解約 claim above
                // for exactly that reason.
                noticeRow(
                    {
                        let date = Self.resetFormatter.string(from: end)
                        return tr(
                            "解約手続き済みです。\(date)まで Pro をご利用いただけます。",
                            "Your subscription is cancelled. Pro stays active until \(date).",
                            "已办理取消。Pro 可使用至\(date)。"
                        )
                    }(),
                    actions: [(tr("解約を取り消す", "Resume subscription", "取消退订"), .overview)]
                )
            } else if entitlement.plan == .pro {
                noticeRow(
                    nil,
                    actions: [
                        (tr("お支払い方法", "Payment method", "付款方式"), .paymentMethod),
                        (tr("請求書", "Invoices", "账单"), .overview),
                        (tr("解約する", "Cancel", "取消订阅"), .cancel),
                    ]
                )
            }

            // The honest replacement for 「税込」. It is the thing 総額表示 exists to
            // guarantee — no amount appears at the card that was not on the page —
            // stated without making a 消費税 claim we cannot make (§10).
            Text(tr(
                "表示価格が実際にご請求される金額です。",
                "The price shown is the amount you are charged.",
                "所示价格即为实际收费金额。"
            ))
                .font(Tokens.Font.body(12))
                .foregroundStyle(Tokens.Window.textTertiary)

            Text(tr(
                "iPhone版の「AIキーボード」はこれからも無料で、上限も変わりません。",
                "The iPhone keyboard stays free, with its own separate limit.",
                "iPhone 版「AIキーボード」将持续免费，上限也不会改变。"
            ))
                .font(Tokens.Font.body(12))
                .foregroundStyle(Tokens.Window.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 解約する is `.secondary` like its neighbours rather than a destructive red.
    /// §10's claim is 「いつでもワンクリックで解約」 and styling the exit as a hazard is
    /// a soft form of the 引き留め the 消費者庁 検討会 objects to — the button should
    /// look as ordinary as the action is.
    private func noticeRow(
        _ message: String?,
        actions: [(String, BillingRemoteStore.PortalFlow)]
    ) -> some View {
        HStack(spacing: 12) {
            if let message {
                Text(message)
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            ForEach(actions, id: \.0) { title, flow in
                ActionButton(title, style: .secondary, enabled: !model.isOpeningBilling) {
                    model.openBillingPortal(flow)
                }
            }
        }
    }

    private var signedOutNotice: some View {
        Card {
            Text(tr("プランを表示するにはサインインしてください。", "Sign in to see your plan.", "请登录后查看套餐。"))
                .font(Tokens.Font.body(13))
                .foregroundStyle(Tokens.Window.textSecondary)
        }
    }

    /// 「10月20日」 — the date only, because the hour is never the interesting part
    /// and a timestamp reads as a system log rather than an answer.
    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = tr("M月d日", "MMMM d", "M月d日")
        return formatter
    }()
}

// MARK: - Card

private struct PlanCard: View {
    enum Action {
        /// The plan the user is on. Rendered as a flat, inert plate — the reference's
        /// "Current Plan": present so the row reads as a comparison, not clickable
        /// because there is nothing to do.
        case current
        case change(title: String, busy: Bool, run: () -> Void)
        case none
    }

    let name: String
    let price: String
    let unit: String
    /// An accent line above the price — today, the welcome offer's deadline. Nil on
    /// every card that has nothing time-bound to say, which is all of them most of
    /// the time.
    var flag: String? = nil
    let caption: String?
    let features: [String]
    let highlighted: Bool
    let action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    if let flag {
                        Text(flag)
                            .font(Tokens.Font.body(11, weight: .medium))
                            .foregroundStyle(Tokens.Window.accentText)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(price)
                            .font(Tokens.Font.display(24))
                            .foregroundStyle(Tokens.Window.textPrimary)
                        Text(unit)
                            .font(Tokens.Font.body(12))
                            .foregroundStyle(Tokens.Window.textSecondary)
                    }
                    if let caption {
                        Text(caption)
                            .font(Tokens.Font.body(11))
                            .foregroundStyle(Tokens.Window.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 8) {
                            Icon(.check, size: 13)
                                .foregroundStyle(Tokens.Window.accent)
                                .padding(.top, 1)
                            Text(feature)
                                .font(Tokens.Font.body(12))
                                .foregroundStyle(Tokens.Window.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: 0)
                actionView
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Window.cardRadius, style: .continuous)
                .fill(Tokens.Window.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Window.cardRadius, style: .continuous)
                .strokeBorder(
                    highlighted ? Tokens.Window.accent : Tokens.Window.hairline,
                    lineWidth: highlighted ? 1.5 : 1
                )
        )
        .clipShape(
            RoundedRectangle(cornerRadius: Tokens.Window.cardRadius, style: .continuous)
        )
    }

    /// The reference gives the recommended plan a saturated header band. Ours is the
    /// accent plate rather than a gradient — `AGENTS.md` §14's rule is that the accent
    /// is flat on the chrome, and the one gradient left in this app is the overlay's
    /// generating capsule.
    private var header: some View {
        HStack {
            Text(name)
                .font(Tokens.Font.body(13, weight: .medium))
                .foregroundStyle(highlighted ? Tokens.Window.accentText : Tokens.Window.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(highlighted ? Tokens.Window.accentPlate : Tokens.Window.group)
    }

    @ViewBuilder
    private var actionView: some View {
        switch action {
        case .current:
            Text(tr("現在のプラン", "Current plan", "当前套餐"))
                .font(Tokens.Font.body(13, weight: .medium))
                .foregroundStyle(Tokens.Window.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Window.buttonRadius, style: .continuous)
                        .fill(Tokens.Window.group)
                )
        case .change(let title, let busy, let run):
            ActionButton(busy ? tr("開いています…", "Opening…", "正在打开…") : title, style: .primary, enabled: !busy, action: run)
                .frame(maxWidth: .infinity)
        case .none:
            EmptyView()
        }
    }
}
