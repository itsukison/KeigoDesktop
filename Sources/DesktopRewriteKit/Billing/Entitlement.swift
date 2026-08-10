import Foundation

/// What the server says this account may do this month.
///
/// **Every field here is computed server-side and none of it is cached across a
/// launch.** `docs/billing.md` §3.4 is the reason: entitlement is a function of
/// `(status, past_due_since, now())`, so a grace window that expires while the app is
/// open has to change the answer without anything being pushed to us. A value cached
/// at sign-in would report `pro` for a fortnight after the account went to `free`.
public struct Entitlement: Sendable, Equatable {

    public enum Plan: String, Sendable, Equatable {
        case free
        case pro

        public var displayName: String {
            switch self {
            case .free: return tr("無料", "Free", "免费")
            case .pro: return "Pro"
            }
        }
    }

    public enum Interval: String, Sendable, Equatable {
        case month
        case year
    }

    public let plan: Plan
    /// Stripe's raw status, for the `past_due` banner. Nil when there has never been
    /// a subscription — absence is a valid state, never an error (§3.1).
    public let status: String?
    public let interval: Interval?

    /// What this subscription is actually billed in, or nil when there is none.
    ///
    /// **Nil is not "yen"** — it is "nothing has been sold yet", and the two answer
    /// differently. A user with no subscription is quoted in whatever their interface
    /// language implies (`BillingCurrency.forInterface`); a user *with* one is quoted
    /// in the currency their card is charged, whatever language they have since
    /// switched to. Every plan surface applies `currency ?? .forInterface(language)`
    /// for that reason, and `PlanPricingTests` pins both halves.
    public let currency: BillingCurrency?

    public let used: Int
    public let monthLimit: Int

    /// **Required on every cap-hit surface and on the ホーム usage row**, per §4.5:
    /// the driver of billing support tickets is an invisible reset date, not the lock.
    /// Never render a fixed date — a Pro window resets on the subscription anchor and
    /// a free one on the 1st, so this is the only true answer for a given user.
    public let resetsAt: Date

    /// Stripe's own field, mirrored exactly. **Do not branch UI on this** — see
    /// `cancelsAt`, which is the question the interface actually asks.
    public let cancelAtPeriodEnd: Bool

    /// When access ends, if a cancellation is scheduled. Nil when none is.
    ///
    /// This exists because `cancelAtPeriodEnd` stopped being the answer. On
    /// `2026-07-29.dahlia` with `billing_mode: flexible`, cancelling at period end
    /// sets Stripe's `cancel_at` and leaves `cancel_at_period_end` FALSE — so the
    /// 解約予定 notice branched on a boolean that a real cancellation never sets, and
    /// the user was told nothing. The server now folds both fields into one date, and
    /// a fixed-date cancellation reports the date it actually falls on rather than
    /// the period boundary.
    public let cancelsAt: Date?

    public let currentPeriodEnd: Date?
    public let pastDueSince: Date?

    /// When the end-of-onboarding welcome offer stops being redeemable, or nil if
    /// this account never opened one.
    ///
    /// The window is minted and enforced by the server — `desktop.welcome_offers`,
    /// read by `desktop-checkout` at the moment a session is created. This field
    /// exists so the interface can *say so* without a second round trip; it is never
    /// what grants the discount. A deadline enforced by the client is not a deadline.
    public let welcomeOfferExpiresAt: Date?

    /// The only welcome-offer test any surface should use.
    ///
    /// Three conditions, and each of them has a surface that would otherwise get it
    /// wrong: the window has to exist, it has to have time left, and the user has to
    /// have something to buy. A Pro user's row can still carry a live window — they
    /// may have subscribed at list price from the ⚙︎ pane before the 72 hours ran
    /// out — and drawing them a discount card for a plan they already own is worse
    /// than drawing nothing.
    public var hasWelcomeOffer: Bool {
        guard plan == .free, let expiry = welcomeOfferExpiresAt else { return false }
        return expiry > Date()
    }

    /// The only cancellation test any surface should use.
    public var isCancelScheduled: Bool { cancelsAt != nil }

    public var remaining: Int { max(0, monthLimit - used) }

    /// Clamped, because `used` is `committed` only and the server already clamps it —
    /// this is belt and braces against a limit change landing mid-window.
    public var fraction: Double {
        guard monthLimit > 0 else { return 0 }
        return min(1, Double(used) / Double(monthLimit))
    }

    /// `past_due` inside the 14-day grace window: still Pro, but the card needs
    /// fixing and §3.4 says to say so rather than wait for the revocation.
    public var needsPaymentAttention: Bool {
        plan == .pro && pastDueSince != nil
    }

    public init(
        plan: Plan,
        status: String?,
        interval: Interval?,
        currency: BillingCurrency?,
        used: Int,
        monthLimit: Int,
        resetsAt: Date,
        cancelAtPeriodEnd: Bool,
        cancelsAt: Date?,
        currentPeriodEnd: Date?,
        pastDueSince: Date?,
        welcomeOfferExpiresAt: Date?
    ) {
        self.plan = plan
        self.status = status
        self.interval = interval
        self.currency = currency
        self.used = used
        self.monthLimit = monthLimit
        self.resetsAt = resetsAt
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
        self.cancelsAt = cancelsAt
        self.currentPeriodEnd = currentPeriodEnd
        self.pastDueSince = pastDueSince
        self.welcomeOfferExpiresAt = welcomeOfferExpiresAt
    }
}

// MARK: - Wire shape

/// One row of `public.desktop_get_entitlement()`.
///
/// `billing_interval`, not `interval`: the SQL function cannot name an OUT parameter
/// `interval` — it is a `col_name_keyword` and reads as a type in plpgsql.
struct EntitlementRow: Decodable {
    let plan: String
    let status: String?
    let billingInterval: String?
    /// Stripe's own lowercase code (`"jpy"` / `"usd"`), mirrored from
    /// `desktop.subscriptions.currency`. Null for an account that has never bought.
    let billingCurrency: String?
    let used: Int
    let monthLimit: Int
    let resetsAt: Date
    let cancelAtPeriodEnd: Bool
    let cancelsAt: Date?
    let currentPeriodEnd: Date?
    let pastDueSince: Date?
    let welcomeOfferExpiresAt: Date?

    var entitlement: Entitlement {
        Entitlement(
            plan: Entitlement.Plan(rawValue: plan) ?? .free,
            status: status,
            interval: billingInterval.flatMap(Entitlement.Interval.init(rawValue:)),
            // An unrecognised currency decodes to nil rather than to a guess: the
            // caller then falls back to the interface language, which is a defensible
            // quote, where a wrong currency is a wrong price.
            currency: billingCurrency.flatMap(BillingCurrency.init(rawValue:)),
            used: used,
            monthLimit: monthLimit,
            resetsAt: resetsAt,
            cancelAtPeriodEnd: cancelAtPeriodEnd,
            cancelsAt: cancelsAt,
            currentPeriodEnd: currentPeriodEnd,
            pastDueSince: pastDueSince,
            welcomeOfferExpiresAt: welcomeOfferExpiresAt
        )
    }
}

/// One row of `public.desktop_start_welcome_offer()`.
///
/// `available` is false when the account is ineligible — it has had a subscription
/// before — and in that case no row was written at all. Absence and refusal are the
/// same answer to the caller and deliberately not distinguished here: the interface
/// draws the offer or it does not.
struct WelcomeOfferRow: Decodable {
    let available: Bool
    let expiresAt: Date?
}

// MARK: - Store

/// Reads entitlement, and opens Stripe Checkout / the Billing Portal.
///
/// Three things about the split, all from `docs/billing.md`:
///
/// - **The read goes straight to PostgREST**, not through an Edge Function.
///   `desktop_get_entitlement()` is the one `desktop_*` entry point granted to
///   `authenticated` (§7), and it takes no arguments — it derives the user from
///   `auth.uid()`. A `p_user_id` parameter on a function `authenticated` can call is
///   an IDOR that reads anyone's plan.
/// - **The writes go through Edge Functions**, because they need the Stripe secret
///   key and the §3.3 race defences, neither of which can live in this binary.
/// - **The price is resolved server-side from a lookup key.**
///   `prompt/src/ipc/billing-handlers.js` takes `priceId` from the client; §7 says
///   plainly not to copy that. We send `pro_monthly_jpy` / `pro_yearly_jpy` and the
///   function maps it.
public struct BillingRemoteStore: Sendable {

    public enum PriceKey: String, Sendable {
        case monthly = "pro_monthly_jpy"
        case yearly = "pro_yearly_jpy"
    }

    private let config: SupabaseConfig
    private let auth: AuthService
    private let session: URLSession

    public init(config: SupabaseConfig, auth: AuthService, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    public func fetchEntitlement() async throws -> Entitlement {
        var request = URLRequest(
            url: config.restEndpoint.appendingPathComponent("rpc/desktop_get_entitlement")
        )
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 15
        try await authorize(&request)

        let data = try await send(request, action: tr("プランを読み込めませんでした。", "Couldn't load your plan.", "无法加载套餐信息。"))
        let rows = try PostgRESTCoding.decoder.decode([EntitlementRow].self, from: data)
        guard let row = rows.first else {
            throw RewriteError.backend(tr("プランを読み込めませんでした。", "Couldn't load your plan.", "无法加载套餐信息。"))
        }
        return row.entitlement
    }

    /// Returns the hosted Checkout URL to open in the browser.
    ///
    /// The server may hand back an *existing* session's URL rather than a new one —
    /// §3.3's `checkout_intents` primary key means a double-click resolves to one
    /// session, not two. That is correct and this call cannot tell the difference.
    ///
    /// **Three things the client says, and one it deliberately does not.** It names
    /// the plan, the currency and the language to render Checkout in. It does *not*
    /// say whether the welcome discount applies — that is read off
    /// `desktop.welcome_offers` inside the function, because a discount a client can
    /// ask for is a discount anyone can take.
    ///
    /// The currency is sent rather than left to Stripe's IP localization on purpose:
    /// Checkout would otherwise quote an English user in Japan in yen after the app
    /// had shown them dollars, and 「表示価格が実際にご請求される金額です」 is a claim
    /// about exactly that gap.
    public func checkoutURL(
        for price: PriceKey,
        currency: BillingCurrency,
        language: AppLanguage
    ) async throws -> URL {
        try await billingURL(
            function: "desktop-checkout",
            body: [
                "price_lookup_key": price.rawValue,
                "currency": currency.rawValue,
                "locale": Self.checkoutLocale(for: language),
            ],
            failure: tr("決済ページを開けませんでした。", "Couldn't open the checkout page.", "无法打开结算页面。")
        )
    }

    /// Stripe Checkout's own locale codes. It takes `zh` for Simplified Chinese —
    /// `zh-Hans` is not one of its values — so this mapping cannot simply be
    /// `AppLanguage.rawValue`.
    static func checkoutLocale(for language: AppLanguage) -> String {
        switch language {
        case .japanese: return "ja"
        case .english: return "en"
        case .simplifiedChinese: return "zh"
        }
    }

    /// Opens the 72-hour welcome-offer window, and returns when it closes.
    ///
    /// Idempotent and **server-authoritative**: called every time the user lands on
    /// the offer page, it mints the window on the first call and returns the same
    /// deadline on every one after it. That is what makes a replayed onboarding, a
    /// relaunch mid-run, or a second Mac unable to extend the offer.
    ///
    /// Returns nil when the account is not eligible — it has bought before — in
    /// which case nothing was written.
    public func startWelcomeOffer() async throws -> Date? {
        var request = URLRequest(
            url: config.restEndpoint.appendingPathComponent("rpc/desktop_start_welcome_offer")
        )
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 15
        try await authorize(&request)

        let data = try await send(
            request,
            action: tr("プランを読み込めませんでした。", "Couldn't load your plan.", "无法加载套餐信息。")
        )
        let rows = try PostgRESTCoding.decoder.decode([WelcomeOfferRow].self, from: data)
        guard let row = rows.first, row.available else { return nil }
        return row.expiresAt
    }

    /// Which screen of the Billing Portal to open on.
    ///
    /// An intent, never a Stripe object: the server maps these to `flow_data` and
    /// looks the subscription id up from the caller's own row (§7). `overview` is
    /// also where un-cancelling lives — Stripe has no renew flow, and the overview
    /// carries the renew button once a cancellation is scheduled.
    public enum PortalFlow: String, Sendable {
        case overview
        case cancel
        case update
        case paymentMethod = "payment_method"
    }

    /// The Billing Portal — cancellation, card updates, invoices.
    ///
    /// 「いつでもワンクリックで解約」 on the paywall is only defensible while it is
    /// literally true (§10), so this is one call with no interstitial of our own —
    /// and `.cancel` makes it literally *fewer* clicks by landing on the cancel
    /// screen instead of the overview.
    public func portalURL(flow: PortalFlow = .overview) async throws -> URL {
        try await billingURL(
            function: "desktop-portal",
            body: flow == .overview ? [:] : ["flow": flow.rawValue],
            failure: tr("お支払い管理を開けませんでした。", "Couldn't open billing management.", "无法打开付款管理。")
        )
    }

    private func billingURL(
        function: String,
        body: [String: String],
        failure: String
    ) async throws -> URL {
        var request = URLRequest(
            url: config.supabaseURL.appendingPathComponent("functions/v1/\(function)")
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 20
        try await authorize(&request)

        let data = try await send(request, action: failure)
        struct Response: Decodable { let url: String }
        guard
            let decoded = try? JSONDecoder().decode(Response.self, from: data),
            let url = URL(string: decoded.url)
        else {
            throw RewriteError.backend(failure)
        }
        return url
    }

    private func send(_ request: URLRequest, action: String) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RewriteError.backend(action)
        }
        return data
    }

    private func authorize(_ request: inout URLRequest) async throws {
        let accessToken = try await auth.ensureFreshAccessToken()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
}
