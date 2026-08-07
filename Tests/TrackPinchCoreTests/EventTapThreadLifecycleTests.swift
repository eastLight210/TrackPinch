import XCTest
@testable import TrackPinchCore

final class EventTapThreadLifecycleTests: XCTestCase {
    func testRetryWaitsForExistingThreadToStopBeforeStartingNextThread() {
        var lifecycle = EventTapThreadLifecycle()

        XCTAssertEqual(lifecycle.requestStart(), .startThread)
        XCTAssertEqual(lifecycle.requestRetry(), .stopThread)
        XCTAssertTrue(lifecycle.hasThread)
        XCTAssertTrue(lifecycle.stopRequested)
        XCTAssertTrue(lifecycle.restartRequested)

        XCTAssertEqual(lifecycle.threadDidStop(), .startThread)
        XCTAssertTrue(lifecycle.hasThread)
        XCTAssertFalse(lifecycle.stopRequested)
        XCTAssertFalse(lifecycle.restartRequested)
    }

    func testRetryStartsImmediatelyWhenNoThreadExists() {
        var lifecycle = EventTapThreadLifecycle()

        XCTAssertEqual(lifecycle.requestRetry(), .startThread)
        XCTAssertTrue(lifecycle.hasThread)
    }

    func testExplicitStopClearsPendingRestart() {
        var lifecycle = EventTapThreadLifecycle()

        _ = lifecycle.requestStart()
        _ = lifecycle.requestRetry()

        XCTAssertEqual(lifecycle.requestStop(), .stopThread)
        XCTAssertFalse(lifecycle.restartRequested)
        XCTAssertEqual(lifecycle.threadDidStop(), .none)
        XCTAssertFalse(lifecycle.hasThread)
    }

    func testStopRequestedBeforeInstallationRemainsVisibleToThread() {
        var lifecycle = EventTapThreadLifecycle()

        _ = lifecycle.requestStart()
        XCTAssertEqual(lifecycle.requestStop(), .stopThread)
        XCTAssertTrue(lifecycle.stopRequested)
    }
}
