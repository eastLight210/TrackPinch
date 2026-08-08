import XCTest
@testable import TrackPinchCore

final class TrackPinchOperationGateTests: XCTestCase {
    func testAllowsCaptureOnlyWhenEveryRequirementIsReady() {
        XCTAssertTrue(
            TrackPinchOperationGate.allowsCapture(
                userEnabled: true,
                accessibilityTrusted: true,
                eventTapHealthy: true
            )
        )
    }

    func testFailsOpenWhenAnyRequirementIsUnavailable() {
        let readinessMatrix = [
            (false, true, true),
            (true, false, true),
            (true, true, false),
        ]

        for state in readinessMatrix {
            XCTAssertFalse(
                TrackPinchOperationGate.allowsCapture(
                    userEnabled: state.0,
                    accessibilityTrusted: state.1,
                    eventTapHealthy: state.2
                )
            )
        }
    }
}
