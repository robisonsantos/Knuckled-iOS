import XCTest
@testable import Knuckled

final class SettingsStoreTests: XCTestCase {

    private func freshStore() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: "test-\(UUID().uuidString)")
        return (SettingsStore(defaults: defaults), defaults)
    }

    func testDefaultsAreAllFalse() {
        let (store, _) = freshStore()
        XCTAssertFalse(store.muted)
        XCTAssertFalse(store.autoRoll)
        XCTAssertFalse(store.onboardingSeen)
    }

    func testTogglesPersistAndReload() {
        let (_, defaults) = freshStore()
        let store = SettingsStore(defaults: defaults)
        store.muted = true
        store.autoRoll = true
        store.onboardingSeen = true
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.muted)
        XCTAssertTrue(reloaded.autoRoll)
        XCTAssertTrue(reloaded.onboardingSeen)
    }

    func testSuitesAreIsolated() {
        let (a, _) = freshStore()
        let (b, _) = freshStore()
        a.muted = true
        XCTAssertFalse(b.muted)
    }
}
