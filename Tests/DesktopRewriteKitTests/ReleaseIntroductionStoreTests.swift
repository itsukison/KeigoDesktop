import XCTest
@testable import DesktopRewriteKit

final class ReleaseIntroductionStoreTests: XCTestCase {
    func testExistingUsersSeeNewIntroductionOnceAcrossRelaunchesAndPatches() {
        let name = "ReleaseIntroductionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ReleaseIntroductionStore(defaults: defaults)
        store.prepare("refresh", onboardingComplete: true)
        XCTAssertTrue(store.shouldPresent("refresh"))
        // Eligibility checks do not count as a presentation or dismissal.
        XCTAssertTrue(store.shouldPresent("refresh"))
        store.acknowledge("refresh")
        let relaunched = ReleaseIntroductionStore(defaults: defaults)
        XCTAssertFalse(relaunched.shouldPresent("refresh"))
        XCTAssertTrue(relaunched.shouldPresent("next-features"))
        relaunched.acknowledge("next-features")
        XCTAssertFalse(relaunched.shouldPresent("refresh"))
    }

    func testFreshInstallLearnsCurrentFeaturesInOnboarding() {
        let name = "ReleaseIntroductionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ReleaseIntroductionStore(defaults: defaults)
        store.prepare("refresh", onboardingComplete: false)
        store.prepare("refresh", onboardingComplete: true)
        XCTAssertFalse(store.shouldPresent("refresh"))
        XCTAssertTrue(store.shouldPresent("next-features"))
        XCTAssertNil(PendingUpdateStore(defaults: defaults).pending(for: "1.0"))
    }
}
