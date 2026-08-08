import CoreGraphics
import XCTest
@testable import TrackPinchCore

final class PopoverSizePolicyTests: XCTestCase {
    func testUsesIdealHeightWhenScreenHasEnoughRoom() {
        XCTAssertEqual(
            PopoverSizePolicy.contentHeight(forVisibleFrameHeight: 900),
            560
        )
    }

    func testShrinksBelowVisibleFrameOnShortScreen() {
        XCTAssertEqual(
            PopoverSizePolicy.contentHeight(forVisibleFrameHeight: 390),
            366
        )
    }

    func testKeepsPositiveHeightWhenAvailableSpaceIsTiny() {
        XCTAssertEqual(
            PopoverSizePolicy.contentHeight(forVisibleFrameHeight: 12),
            1
        )
    }

    func testFallsBackToIdealHeightForInvalidMeasurements() {
        XCTAssertEqual(
            PopoverSizePolicy.contentHeight(forVisibleFrameHeight: .nan),
            560
        )
        XCTAssertEqual(
            PopoverSizePolicy.contentHeight(forVisibleFrameHeight: -1),
            560
        )
    }
}
