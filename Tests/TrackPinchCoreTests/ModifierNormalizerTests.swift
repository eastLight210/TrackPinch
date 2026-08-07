import AppKit
import XCTest
@testable import TrackPinchCore

final class ModifierNormalizerTests: XCTestCase {
    func testDefaultGestureModifiersUseExternalKeyboardSafeChord() {
        XCTAssertEqual(
            ModifierNormalizer.defaultGestureModifiers,
            [.control, .option, .command]
        )
        XCTAssertTrue(
            ModifierNormalizer.matches(
                [.control, .option, .command, .capsLock],
                configured: ModifierNormalizer.defaultGestureModifiers
            )
        )
        XCTAssertFalse(
            ModifierNormalizer.matches(
                [.control, .option],
                configured: ModifierNormalizer.defaultGestureModifiers
            )
        )
    }

    func testIgnoresCapsLockAndDeviceDependentFlags() {
        let input: NSEvent.ModifierFlags = [
            .function,
            .capsLock,
            .numericPad,
        ]

        XCTAssertEqual(ModifierNormalizer.normalized(input), [.function])
    }

    func testRequiresAnExactSupportedModifierMatch() {
        XCTAssertTrue(
            ModifierNormalizer.matches(
                [.function, .capsLock],
                configured: [.function]
            )
        )
        XCTAssertFalse(
            ModifierNormalizer.matches(
                [.function, .shift],
                configured: [.function]
            )
        )
    }

    func testDescriptionUsesStableOrdering() {
        XCTAssertEqual(
            ModifierNormalizer.description(of: [.shift, .option, .function]),
            "Fn+Option+Shift"
        )
    }
}
