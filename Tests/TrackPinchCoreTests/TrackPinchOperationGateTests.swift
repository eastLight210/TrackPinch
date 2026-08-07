import XCTest
@testable import TrackPinchCore

final class TrackPinchOperationGateTests: XCTestCase {
    func testAllowsCaptureOnlyWhenEveryRequirementIsReady() {
        XCTAssertTrue(
            TrackPinchOperationGate.allowsCapture(
                userEnabled: true,
                accessibilityTrusted: true,
                inputListeningGranted: true,
                eventTapHealthy: true
            )
        )
    }

    func testFailsOpenWhenAnyRequirementIsUnavailable() {
        let readinessMatrix = [
            (false, true, true, true),
            (true, false, true, true),
            (true, true, false, true),
            (true, true, true, false),
        ]

        for state in readinessMatrix {
            XCTAssertFalse(
                TrackPinchOperationGate.allowsCapture(
                    userEnabled: state.0,
                    accessibilityTrusted: state.1,
                    inputListeningGranted: state.2,
                    eventTapHealthy: state.3
                )
            )
        }
    }
}
