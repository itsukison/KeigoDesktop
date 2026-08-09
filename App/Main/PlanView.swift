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
///   ¥3,360 — 2.27 months. §4 sells the annual plan on the ¥1,200/月相当 figure so
///   the buyer compares 1,200 against 1,480 in one step with no arithmetic; a
///   「Save 20%」 badge asks them to do the multiplication instead.
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

    // MARK: - Interval

    private var intervalToggle: some View {
        HStack(spacing: 0) {
            segment(.year, title: "年払い", badge: "2ヶ月分お得")
            segment(.month, title: "月払い", badge: nil)
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
                name: "無料",
                price: "¥0",
                unit: "/ 月",
                caption: nil,
                features: [
                    "月50回まで書き換え",
                    "自分のボタンをそのまま同期",
                    "どのアプリでも使える",
                ],
                highlighted: false,
                action: plan == .free
                    ? .current
                    : .none
            )

            PlanCard(
                name: "Pro",
                price: interval == .year ? "¥1,200" : "¥1,480",
                unit: interval == .year ? "/ 月相当" : "/ 月",
                // **Not 「税込」.** Core7 is a 免税事業者 and not an 適格請求書発行事業者
                // (`docs/billing.md` §10), so a 消費税 claim is one we are not in a
                // position to make. 消費税法第63条's 総額表示義務 explicitly excludes
                // 免税事業者, so nothing requires the word either — what the buyer
                // needs is the amount that will actually be charged, which is what
                // this says. 自動更新 stays because 特商法第12条の6 ①分量 requires it.
                caption: interval == .year ? "年 ¥14,400 を一括・自動更新" : "毎月 ¥1,480 を自動更新",
                features: [
                    "月1,000回まで書き換え",
                    "通常のご利用では到達しません",
                    "いつでもワンクリックで解約",
                ],
                highlighted: true,
                action: proAction
            )
        }
        .fixedSize(horizontal: false, vertical: true)
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
                title: interval == .year ? "年払いに変更" : "月払いに変更",
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
            title: "アップグレード",
            busy: model.isOpeningBilling,
            run: { model.beginCheckout(interval == .year ? .yearly : .monthly) }
        )
    }

    // MARK: - Usage

    /// §3's requirement, and the one row that has to be here whatever else is:
    /// a quota the user cannot see is a quota that ambushes them.
    private func usage(_ entitlement: Entitlement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "今月の書き換え")
            Card(padding: 16, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(entitlement.used) / \(entitlement.monthLimit)")
                        .font(Tokens.Font.display(20))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text("回")
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                    Spacer()
                    Text("\(Self.resetFormatter.string(from: entitlement.resetsAt))にリセット")
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
                    "お支払いを確認できませんでした。カード情報を更新してください。",
                    actions: [("お支払い方法を更新", .paymentMethod)]
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
                    "解約手続き済みです。\(Self.resetFormatter.string(from: end))まで Pro をご利用いただけます。",
                    actions: [("解約を取り消す", .overview)]
                )
            } else if entitlement.plan == .pro {
                noticeRow(
                    nil,
                    actions: [
                        ("お支払い方法", .paymentMethod),
                        ("請求書", .overview),
                        ("解約する", .cancel),
                    ]
                )
            }

            // The honest replacement for 「税込」. It is the thing 総額表示 exists to
            // guarantee — no amount appears at the card that was not on the page —
            // stated without making a 消費税 claim we cannot make (§10).
            Text("表示価格が実際にご請求される金額です。")
                .font(Tokens.Font.body(12))
                .foregroundStyle(Tokens.Window.textTertiary)

            Text("iPhone版の「AIキーボード」はこれからも無料で、上限も変わりません。")
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
            Text("プランを表示するにはサインインしてください。")
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
        formatter.dateFormat = "M月d日"
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
    let caption: String?
    let features: [String]
    let highlighted: Bool
    let action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
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
            Text("現在のプラン")
                .font(Tokens.Font.body(13, weight: .medium))
                .foregroundStyle(Tokens.Window.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Window.buttonRadius, style: .continuous)
                        .fill(Tokens.Window.group)
                )
        case .change(let title, let busy, let run):
            ActionButton(busy ? "開いています…" : title, style: .primary, enabled: !busy, action: run)
                .frame(maxWidth: .infinity)
        case .none:
            EmptyView()
        }
    }
}
