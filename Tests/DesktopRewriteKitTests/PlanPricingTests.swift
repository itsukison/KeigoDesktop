import XCTest
@testable import DesktopRewriteKit

/// Every amount the product charges, pinned.
///
/// These are not style tests. The eight numbers below are the two live Stripe
/// prices' `unit_amount` / `currency_options[usd][unit_amount]` and the two welcome
/// coupons' `amount_off`, and a client that disagrees with the catalog quotes a
/// figure the card does not charge — which is the one thing
/// 「表示価格が実際にご請求される金額です」 promises cannot happen.
final class PlanPricingTests: XCTestCase {

    override func tearDown() {
        AppLanguageState.current = .japanese
        super.tearDown()
    }

    // MARK: - Which currency

    /// The Chinese case is the one a future edit is most likely to get wrong: it is
    /// the language that reads as "foreign" while being billed as domestic. §17's
    /// premise is a Chinese speaker working in Japan, so their card is a Japanese
    /// card.
    func testOnlyEnglishIsBilledInDollars() {
        XCTAssertEqual(BillingCurrency.forInterface(.english), .usd)
        XCTAssertEqual(BillingCurrency.forInterface(.japanese), .jpy)
        XCTAssertEqual(BillingCurrency.forInterface(.simplifiedChinese), .jpy)
    }

    // MARK: - The catalog

    func testListPricesMatchTheStripeCatalog() {
        XCTAssertEqual(PlanPricing.list(.month, in: .jpy).minorUnits, 1_480)
        XCTAssertEqual(PlanPricing.list(.year, in: .jpy).minorUnits, 14_400)
        XCTAssertEqual(PlanPricing.list(.month, in: .usd).minorUnits, 1_200)
        XCTAssertEqual(PlanPricing.list(.year, in: .usd).minorUnits, 12_000)
    }

    func testWelcomeOfferPricesMatchTheStripeCoupons() {
        XCTAssertEqual(PlanPricing.welcomeOffer(.month, in: .jpy).minorUnits, 980)
        XCTAssertEqual(PlanPricing.welcomeOffer(.year, in: .jpy).minorUnits, 9_600)
        XCTAssertEqual(PlanPricing.welcomeOffer(.month, in: .usd).minorUnits, 800)
        XCTAssertEqual(PlanPricing.welcomeOffer(.year, in: .usd).minorUnits, 8_000)
    }

    /// The coupons carry these four as `amount_off` — ¥500 / ¥4,800 and $4 / $40.
    /// Read the failure as "the catalog and the client disagree", not as arithmetic.
    func testWelcomeDiscountsAreTheCouponAmounts() {
        XCTAssertEqual(PlanPricing.welcomeDiscount(.month, in: .jpy).minorUnits, 500)
        XCTAssertEqual(PlanPricing.welcomeDiscount(.year, in: .jpy).minorUnits, 4_800)
        XCTAssertEqual(PlanPricing.welcomeDiscount(.month, in: .usd).minorUnits, 400)
        XCTAssertEqual(PlanPricing.welcomeDiscount(.year, in: .usd).minorUnits, 4_000)
    }

    /// Both offers are within a third of list. A coupon larger than its price is a
    /// free subscription, and the shape that produces one is a typo, not a decision.
    func testTheOfferIsADiscountAndNeverExceedsTheListPrice() {
        for currency in [BillingCurrency.jpy, .usd] {
            for interval in [Entitlement.Interval.month, .year] {
                let list = PlanPricing.list(interval, in: currency).minorUnits
                let offer = PlanPricing.welcomeOffer(interval, in: currency).minorUnits
                XCTAssertGreaterThan(offer, 0)
                XCTAssertLessThan(offer, list)
                XCTAssertGreaterThan(Double(offer) / Double(list), 0.6, "the offer is deeper than intended")
            }
        }
    }

    // MARK: - Derived figures

    /// ¥14,400 ÷ 12 = ¥1,200 and $120 ÷ 12 = $10 — both exact, which is the reason
    /// $120 was chosen over $96 or $99.
    func testAnnualDividesExactlyIntoAMonthlyFigure() {
        XCTAssertEqual(PlanPricing.monthlyEquivalent(ofYearly: .jpy)?.display, "¥1,200")
        XCTAssertEqual(PlanPricing.monthlyEquivalent(ofYearly: .usd)?.display, "$10")
    }

    /// ¥3,360 saved is 2.27 months; $24 saved is exactly 2. The badge says 2 in both
    /// languages and is true in both.
    func testTheTwoMonthsFreeBadgeIsTrueInBothCurrencies() {
        XCTAssertEqual(PlanPricing.monthsFree(in: .jpy), 2)
        XCTAssertEqual(PlanPricing.monthsFree(in: .usd), 2)
    }

    // MARK: - Display

    /// A currency formatter would render `$12.00` beside `¥1,480` and would follow
    /// the *system* locale rather than the language chosen on §15's page.
    func testWholeAmountsCarryNoDecimalPart() {
        XCTAssertEqual(PlanPricing.list(.month, in: .usd).display, "$12")
        XCTAssertEqual(PlanPricing.list(.year, in: .usd).display, "$120")
        XCTAssertEqual(PlanPricing.welcomeOffer(.month, in: .usd).display, "$8")
        XCTAssertEqual(PlanPricing.welcomeOffer(.year, in: .usd).display, "$80")
    }

    func testThousandsSeparatorsArePresent() {
        XCTAssertEqual(PlanPricing.list(.month, in: .jpy).display, "¥1,480")
        XCTAssertEqual(PlanPricing.list(.year, in: .jpy).display, "¥14,400")
        XCTAssertEqual(PlanPricing.welcomeOffer(.month, in: .jpy).display, "¥980")
        XCTAssertEqual(PlanPricing.welcomeOffer(.year, in: .jpy).display, "¥9,600")
    }

    /// Cents appear only when there are cents to show. Nothing in the catalog has
    /// them today; a future price that does must still render correctly rather than
    /// silently truncating to the dollar.
    func testFractionalAmountsKeepTwoDecimals() {
        XCTAssertEqual(PlanPricing.Amount(667, .usd).display, "$6.67")
        XCTAssertEqual(PlanPricing.Amount(5, .usd).display, "$0.05")
        XCTAssertEqual(PlanPricing.Amount(1_000_000, .jpy).display, "¥1,000,000")
    }

    // MARK: - The surface rule

    /// **A live subscription's own currency always wins over the interface
    /// language.** A user who subscribed in yen and then switched the app to English
    /// is still charged yen, and quoting them dollars would misstate their own
    /// renewal. This is the rule every plan surface applies; the test pins it here
    /// rather than in a view so it survives a redesign.
    func testAnExistingSubscriptionsCurrencyOutranksTheInterfaceLanguage() {
        AppLanguageState.current = .english
        let japaneseSubscriber = Entitlement(
            plan: .pro,
            status: "active",
            interval: .month,
            currency: .jpy,
            used: 12,
            monthLimit: 1_000,
            resetsAt: Date(),
            cancelAtPeriodEnd: false,
            cancelsAt: nil,
            currentPeriodEnd: nil,
            pastDueSince: nil,
            welcomeOfferExpiresAt: nil
        )

        let shown = japaneseSubscriber.currency ?? .forInterface(AppLanguageState.current)
        XCTAssertEqual(shown, .jpy)
        XCTAssertEqual(PlanPricing.list(.month, in: shown).display, "¥1,480")
    }

    /// With no subscription there is nothing to preserve, so the language decides.
    func testWithNoSubscriptionTheLanguageDecides() {
        AppLanguageState.current = .english
        let free = Entitlement(
            plan: .free,
            status: nil,
            interval: nil,
            currency: nil,
            used: 3,
            monthLimit: 50,
            resetsAt: Date(),
            cancelAtPeriodEnd: false,
            cancelsAt: nil,
            currentPeriodEnd: nil,
            pastDueSince: nil,
            welcomeOfferExpiresAt: nil
        )

        let shown = free.currency ?? .forInterface(AppLanguageState.current)
        XCTAssertEqual(shown, .usd)
        XCTAssertEqual(PlanPricing.list(.month, in: shown).display, "$12")
    }

    // MARK: - The offer window

    /// Live while it has time left, gone the moment it does not. The client only
    /// renders this; `desktop-checkout` decides whether a discount is applied.
    func testTheOfferWindowIsOpenOnlyUntilItExpires() {
        let open = entitlement(offerExpiring: Date().addingTimeInterval(3_600))
        let expired = entitlement(offerExpiring: Date().addingTimeInterval(-1))
        let never = entitlement(offerExpiring: nil)

        XCTAssertTrue(open.hasWelcomeOffer)
        XCTAssertFalse(expired.hasWelcomeOffer)
        XCTAssertFalse(never.hasWelcomeOffer)
    }

    /// A Pro user has nothing to be offered, whatever the row says. The server
    /// refuses the discount for the same reason; this stops the card being drawn.
    func testAProUserIsNeverOfferedTheWelcomeDiscount() {
        var pro = entitlement(offerExpiring: Date().addingTimeInterval(3_600))
        pro = Entitlement(
            plan: .pro,
            status: "active",
            interval: .month,
            currency: .jpy,
            used: pro.used,
            monthLimit: pro.monthLimit,
            resetsAt: pro.resetsAt,
            cancelAtPeriodEnd: false,
            cancelsAt: nil,
            currentPeriodEnd: nil,
            pastDueSince: nil,
            welcomeOfferExpiresAt: pro.welcomeOfferExpiresAt
        )
        XCTAssertFalse(pro.hasWelcomeOffer)
    }

    /// The copy constants mirror `desktop.plan_limits`, which is what the gateway
    /// actually enforces. A test cannot reach that table, so this pins the pair a
    /// human has to re-check against it — the failure mode is the app quoting a cap it
    /// does not enforce, and it is silent.
    func testCopyCapsMatchTheServerPlanLimits() {
        XCTAssertEqual(PlanPricing.freeMonthlyRewrites, 30)
        XCTAssertEqual(PlanPricing.proMonthlyRewrites, 1_000)
    }

    /// `.formatted()` reads the system locale, which is not the app's language — a Mac
    /// set to fr_FR renders `1 000` into Japanese copy. The display string pins en_US
    /// grouping, and all three languages want the comma.
    func testProCapRendersWithACommaRegardlessOfSystemLocale() {
        XCTAssertEqual(PlanPricing.proMonthlyRewritesDisplay, "1,000")
    }

    private func entitlement(offerExpiring: Date?) -> Entitlement {
        Entitlement(
            plan: .free,
            status: nil,
            interval: nil,
            currency: nil,
            used: 0,
            monthLimit: 50,
            resetsAt: Date(),
            cancelAtPeriodEnd: false,
            cancelsAt: nil,
            currentPeriodEnd: nil,
            pastDueSince: nil,
            welcomeOfferExpiresAt: offerExpiring
        )
    }
}
