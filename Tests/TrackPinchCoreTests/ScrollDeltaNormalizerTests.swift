import CoreGraphics
import XCTest
@testable import TrackPinchCore

final class ScrollDeltaNormalizerTests: XCTestCase {
    func testConvertsNonInvertedScrollDeltasToFingerMovement() {
        XCTAssertEqual(
            ScrollDeltaNormalizer.deviceIndependent(
                x: 12,
                y: -8,
                isDirectionInvertedFromDevice: false
            ),
            CGPoint(x: -12, y: 8)
        )
    }

    func testConvertsNaturallyInvertedScrollDeltasToFingerMovement() {
        XCTAssertEqual(
            ScrollDeltaNormalizer.deviceIndependent(
                x: 12,
                y: -8,
                isDirectionInvertedFromDevice: true
            ),
            CGPoint(x: 12, y: -8)
        )
    }
}
