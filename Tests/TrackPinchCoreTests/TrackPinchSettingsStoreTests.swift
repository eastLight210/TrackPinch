import AppKit
import XCTest
@testable import TrackPinchCore

final class TrackPinchSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "TrackPinchSettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLoadsProductDefaultsWhenNothingWasSaved() {
        let settings = TrackPinchSettingsStore(defaults: defaults).load()

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.sensitivity, 1.0)
        XCTAssertEqual(
            settings.modifiers,
            ModifierNormalizer.defaultGestureModifiers
        )
        XCTAssertFalse(settings.hasPresentedOnboarding)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    func testPersistsSettings() {
        let store = TrackPinchSettingsStore(defaults: defaults)
        let expected = TrackPinchSettings(
            isEnabled: false,
            sensitivity: 1.7,
            modifiers: [.control, .shift],
            hasPresentedOnboarding: true,
            hasCompletedOnboarding: true
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testClampsSensitivityAndRejectsEmptyModifiers() {
        let settings = TrackPinchSettings(
            sensitivity: 99,
            modifiers: []
        )

        XCTAssertEqual(settings.sensitivity, 3.0)
        XCTAssertEqual(
            settings.modifiers,
            ModifierNormalizer.defaultGestureModifiers
        )
    }
}
