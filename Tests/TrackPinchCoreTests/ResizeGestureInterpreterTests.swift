import CoreGraphics
import XCTest
@testable import TrackPinchCore

final class ResizeGestureInterpreterTests: XCTestCase {
    func testDeadZoneMovementIsDiscardedWhenHorizontalModeLocks() {
        var interpreter = ResizeGestureInterpreter()

        XCTAssertNil(interpreter.ingest(CGPoint(x: 4, y: 1)))
        XCTAssertNil(interpreter.ingest(CGPoint(x: 5, y: 1)))
        XCTAssertEqual(interpreter.mode, .horizontal)
        XCTAssertEqual(
            interpreter.ingest(CGPoint(x: 3, y: 9)),
            CGSize(width: 3, height: 0)
        )
    }

    func testVerticalModeOnlyChangesHeight() {
        var interpreter = ResizeGestureInterpreter()

        XCTAssertNil(interpreter.ingest(CGPoint(x: 1, y: -9)))
        XCTAssertEqual(interpreter.mode, .vertical)
        XCTAssertEqual(
            interpreter.ingest(CGPoint(x: 7, y: -4)),
            CGSize(width: 0, height: -4)
        )
    }

    func testDiagonalModeChangesBothDimensions() {
        var interpreter = ResizeGestureInterpreter()

        XCTAssertNil(interpreter.ingest(CGPoint(x: 6, y: 6)))
        XCTAssertEqual(interpreter.mode, .diagonal)
        XCTAssertEqual(
            interpreter.ingest(CGPoint(x: -2, y: 5)),
            CGSize(width: -2, height: 5)
        )
    }

    func testSharedSensitivityScalesBothDimensions() {
        var interpreter = ResizeGestureInterpreter(
            horizontalSensitivity: 1.5,
            verticalSensitivity: 1.5
        )

        XCTAssertNil(interpreter.ingest(CGPoint(x: 6, y: 6)))
        XCTAssertEqual(
            interpreter.ingest(CGPoint(x: 2, y: -4)),
            CGSize(width: 3, height: -6)
        )
    }

    func testNonFiniteInputIsIgnored() {
        var interpreter = ResizeGestureInterpreter()

        XCTAssertNil(
            interpreter.ingest(CGPoint(x: CGFloat.infinity, y: 2))
        )
        XCTAssertNil(interpreter.mode)
    }
}
