import Foundation

/// What a subscription is billed in.
///
/// **Two currencies, chosen by the interface language, and that rule lives here
/// only.** `AGENTS.md` §17 used to say plainly that *"amounts never change with the
/// language"* — the product was billed in yen on every surface, and a converted
/// figure on the page would not have been the figure at the card. English pricing
/// reverses that for one language: an English user is quoted **and charged** in USD,
/// so the sentence stays true even though the number no longer does.
///
/// 简体中文 stays on yen. §17's whole premise is that a 简体中文 user is a Chinese
/// speaker working in Japan, so their card is a Japanese card and their price is a
/// Japanese price. This mirrors `AppLanguage.writesJapanese`: one fact, decided in
/// one place, never re-derived from the raw language anywhere else.
public enum BillingCurrency: String, Sendable, Codable, Equatable {
    case jpy
    case usd

    /// The currency an interface language is quoted and charged in.
    public static func forInterface(_ language: AppLanguage) -> BillingCurrency {
        language == .english ? .usd : .jpy
    }

    /// Stripe counts JPY in whole yen and USD in cents. Every amount in this file is
    /// in **minor units** for that reason: they are the numbers that go on the wire,
    /// so the client and the catalog can be compared without a conversion in between.
    public var minorUnitsPerMajor: Int {
        switch self {
        case .jpy: return 1
        case .usd: return 100
        }
    }

    public var symbol: String {
        switch self {
        case .jpy: return "¥"
        case .usd: return "$"
        }
    }
}

/// Every amount this product charges, and the only place any of them is written.
///
/// `docs/pricing.md` §1 and `docs/billing.md` §2 are the authority; this is their
/// transcription into the client. The rule is that **no view may hold a number** —
/// `PlanView` held `"¥1,200"` / `"¥1,480"` / `"¥14,400"` as literals inside `tr()`
/// calls, which is how English shipped quoting yen in English sentences, and how a
/// price change would have needed three edits in three languages to stay consistent.
public enum PlanPricing {

    // MARK: - Amount

    /// A price, in minor units, with the currency it is denominated in.
    public struct Amount: Sendable, Equatable {
        public let minorUnits: Int
        public let currency: BillingCurrency

        public init(_ minorUnits: Int, _ currency: BillingCurrency) {
            self.minorUnits = minorUnits
            self.currency = currency
        }

        /// 「¥1,480」, 「$12」, 「$120」.
        ///
        /// **Hand-rolled rather than `NumberFormatter(.currency)`**, for two reasons
        /// that both produce a visibly wrong price rather than a formatting nit.
        /// A currency formatter follows the *system* locale, not the language chosen
        /// on §15's page, so an English user on a Japanese Mac would read
        /// `US$12.00`; and it renders whole dollars with the cents, so a `$12` plan
        /// becomes `$12.00` next to a `¥1,480` that has no decimal part at all.
        /// The decimals appear only when there is something after the point to say.
        public var display: String {
            let per = currency.minorUnitsPerMajor
            let major = minorUnits / per
            let remainder = minorUnits % per
            var text = currency.symbol + Self.grouped(major)
            if remainder != 0 {
                text += "." + String(format: "%02d", remainder)
            }
            return text
        }

        /// Thousands separators, which a price of this size needs and which the
        /// hand-rolled path above would otherwise drop: `¥14400` reads as a
        /// different order of magnitude at a glance.
        private static func grouped(_ value: Int) -> String {
            let digits = Array(String(abs(value)))
            var out: [Character] = []
            for (offset, digit) in digits.enumerated() {
                if offset > 0 && (digits.count - offset) % 3 == 0 { out.append(",") }
                out.append(digit)
            }
            return (value < 0 ? "-" : "") + String(out)
        }
    }

    // MARK: - The catalog

    /// List price. These four numbers **are** the two Stripe prices' `unit_amount`
    /// and their `currency_options[usd][unit_amount]`
    /// (`price_1U22r6CZmA6ItMhqL2dvxwui`, `price_1U22qkCZmA6ItMhqG9BcunGs`); a change
    /// here without a change there quotes a figure the card never charges, which is
    /// exactly what 「表示価格が実際にご請求される金額です」 promises will not happen.
    public static func list(_ interval: Entitlement.Interval, in currency: BillingCurrency) -> Amount {
        switch (interval, currency) {
        case (.month, .jpy): return Amount(1_480, .jpy)
        case (.year,  .jpy): return Amount(14_400, .jpy)
        case (.month, .usd): return Amount(1_200, .usd)   // $12.00
        case (.year,  .usd): return Amount(12_000, .usd)  // $120.00
        }
    }

    /// The end-of-onboarding welcome offer: **33% off the first period**, then list.
    ///
    /// Annual ¥9,600 / $80 for the first year; monthly ¥980 / $8 for the first three
    /// months. Every one of the four is a round number in its own currency, which is
    /// why the Stripe coupons carry `amount_off` with `currency_options` rather than
    /// a single `percent_off` — a flat 33% produces ¥888 and $7.20.
    public static func welcomeOffer(_ interval: Entitlement.Interval, in currency: BillingCurrency) -> Amount {
        switch (interval, currency) {
        case (.month, .jpy): return Amount(980, .jpy)
        case (.year,  .jpy): return Amount(9_600, .jpy)
        case (.month, .usd): return Amount(800, .usd)    // $8.00
        case (.year,  .usd): return Amount(8_000, .usd)  // $80.00
        }
    }

    /// What the Stripe coupon takes off, per period. Derived rather than written
    /// down twice: this is the number the catalog carries as `amount_off`, and
    /// deriving it means the coupon can never drift from the price it discounts.
    public static func welcomeDiscount(
        _ interval: Entitlement.Interval,
        in currency: BillingCurrency
    ) -> Amount {
        Amount(
            list(interval, in: currency).minorUnits - welcomeOffer(interval, in: currency).minorUnits,
            currency
        )
    }

    /// How many billing periods the monthly offer covers. The annual offer is
    /// `duration: once` and covers exactly one year, so it needs no equivalent.
    public static let welcomeOfferMonthlyPeriods = 3

    /// How long the offer stays open after the user reaches the offer page.
    ///
    /// **The server is authoritative** — `desktop.welcome_offers.expires_at` is what
    /// `desktop-checkout` reads, and this constant only writes the copy. A deadline
    /// enforced by the client is not a deadline, and 景表法's 有利誤認 makes a
    /// deliberately unenforced one a claim rather than a formatting choice.
    public static let welcomeOfferWindowHours = 72

    /// The monthly rewrite caps, for copy only.
    ///
    /// **`desktop.plan_limits` is authoritative** — the gateway reads that table and a
    /// number here can only ever describe it. These exist because the same two figures
    /// were written out by hand in the plan card, the offer page and the quota-exhausted
    /// toast, and a limit change has to reach all three or the app quotes a cap it does
    /// not enforce. Anywhere an entitlement is already loaded, prefer
    /// `Entitlement.monthLimit`: that came from the server and is right even when these
    /// are stale.
    public static let freeMonthlyRewrites = 30
    public static let proMonthlyRewrites = 1_000

    /// `proMonthlyRewrites` as all three languages write it: `1,000`.
    ///
    /// Grouping is pinned to `en_US` rather than taken from `.formatted()`, because
    /// that reads the *system* locale, which is not the app's language (§17) — a Mac
    /// set to French would render `1 000` inside otherwise Japanese copy. All three of
    /// our languages comma-group at thousands, so one pinned format serves them all.
    public static var proMonthlyRewritesDisplay: String {
        proMonthlyRewrites.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    // MARK: - Derived figures

    /// The annual plan's per-month figure, or **nil when the division is not exact**.
    ///
    /// §4 sells the annual plan on this number so the buyer compares ¥1,200 against
    /// ¥1,480 in one step with no arithmetic. Both list prices divide exactly —
    /// ¥14,400 → ¥1,200 and $120 → $10, which is the reason $120 was chosen over
    /// $96 or $99. Returning nil rather than a rounded figure is deliberate: the
    /// annual *offer* (¥9,600 → ¥800, but $80 → $6.66…) has no honest monthly
    /// equivalent in USD, and the card must show the total instead of inventing a
    /// precision the price does not have.
    public static func monthlyEquivalent(ofYearly currency: BillingCurrency) -> Amount? {
        let yearly = list(.year, in: currency).minorUnits
        guard yearly % 12 == 0 else { return nil }
        return Amount(yearly / 12, currency)
    }

    /// 「あと23時間」 / "23 hours left" — how long the welcome offer has, or nil once
    /// it has none.
    ///
    /// One wording, in one place, because three surfaces say it (the onboarding offer
    /// page, the ホーム card and the plan pane) and three surfaces disagreeing about
    /// how long is left reads as three different offers. Hours while there is more
    /// than one, minutes after that: a countdown to the second would be urgency
    /// theatre, and 景表法's 有利誤認 is the reason this deadline is stated plainly and
    /// then actually enforced by `desktop-checkout`.
    public static func offerRemainingText(until expiry: Date, now: Date = Date()) -> String? {
        let seconds = expiry.timeIntervalSince(now)
        guard seconds > 0 else { return nil }

        if seconds >= 3_600 {
            let hours = Int(seconds / 3_600)
            return tr(
                "あと\(hours)時間",
                hours == 1 ? "1 hour left" : "\(hours) hours left",
                "剩余\(hours)小时"
            )
        }
        // Never 「あと0分」: a live offer with under a minute on it still has time,
        // and rounding it to zero tells the user it is gone while the button works.
        let minutes = max(1, Int(seconds / 60))
        return tr(
            "あと\(minutes)分",
            minutes == 1 ? "1 minute left" : "\(minutes) minutes left",
            "剩余\(minutes)分钟"
        )
    }

    /// The 「2ヶ月分お得」 / "2 months free" badge, computed rather than asserted.
    ///
    /// ¥1,480 × 12 = ¥17,760 against ¥14,400 saves ¥3,360 — 2.27 months, floored to
    /// 2. $12 × 12 = $144 against $120 saves exactly $24, which **is** two months.
    /// The badge is therefore literally true in both currencies, and it stays true
    /// only as long as this is derived; a hard-coded 2 beside a changed price is the
    /// failure this exists to prevent.
    public static func monthsFree(in currency: BillingCurrency) -> Int {
        let monthly = list(.month, in: currency).minorUnits
        guard monthly > 0 else { return 0 }
        let saving = monthly * 12 - list(.year, in: currency).minorUnits
        return max(0, saving / monthly)
    }
}
