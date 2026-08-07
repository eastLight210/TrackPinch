import XCTest
@testable import TrackPinchCore

final class CaptureStateMachineTests: XCTestCase {
    func testUnavailableRuntimePassesNewGestureThrough() {
        var machine = CaptureStateMachine()

        let decision = machine.handleScroll(
            input(canBegin: false, canContinue: false, isNew: true)
        )

        XCTAssertFalse(decision.shouldConsume)
        XCTAssertTrue(decision.actions.isEmpty)
        XCTAssertEqual(machine.state, .idle)
    }

    func testReadyRuntimeBeginsAndSubmitsGesture() {
        var machine = CaptureStateMachine()

        let decision = machine.handleScroll(
            input(canBegin: true, canContinue: true, isNew: true)
        )

        XCTAssertTrue(decision.shouldConsume)
        XCTAssertEqual(
            decision.actions,
            [.begin(generation: 1), .submitDelta(generation: 1)]
        )
        XCTAssertEqual(machine.state, .physical(generation: 1))
    }

    func testRuntimeLossCancelsResizeButSwallowsOwnedSequence() {
        var machine = CaptureStateMachine()
        _ = machine.handleScroll(
            input(canBegin: true, canContinue: true, isNew: true)
        )

        let unavailable = machine.handleScroll(
            input(canBegin: false, canContinue: false)
        )

        XCTAssertTrue(unavailable.shouldConsume)
        XCTAssertEqual(unavailable.actions, [.cancel(generation: 1)])
        XCTAssertEqual(machine.state, .swallowing(generation: 1))

        let physicalEnd = machine.handleScroll(
            input(
                canBegin: false,
                canContinue: false,
                isPhysicalEnd: true
            )
        )
        XCTAssertTrue(physicalEnd.shouldConsume)
        XCTAssertEqual(
            machine.state,
            .draining(generation: 1, deadline: 0.3)
        )

        let nextGesture = machine.handleScroll(
            input(
                now: 0.4,
                canBegin: false,
                canContinue: false,
                isNew: true
            )
        )
        XCTAssertFalse(nextGesture.shouldConsume)
        XCTAssertEqual(machine.state, .idle)
    }

    func testModifierReleaseStopsResizeAndKeepsOwnership() {
        var machine = CaptureStateMachine()
        _ = machine.handleScroll(
            input(canBegin: true, canContinue: true, isNew: true)
        )

        XCTAssertEqual(machine.stopResizing(), .cancel(generation: 1))
        XCTAssertEqual(machine.state, .swallowing(generation: 1))
    }

    func testRecoverableInterruptionKeepsOwnershipThroughMomentumEnd() {
        var machine = CaptureStateMachine()
        _ = machine.handleScroll(
            input(canBegin: true, canContinue: true, isNew: true)
        )

        XCTAssertEqual(
            machine.stopResizing(at: 1),
            .cancel(generation: 1)
        )
        XCTAssertEqual(machine.state, .swallowing(generation: 1))

        let physicalTail = machine.handleScroll(
            input(now: 1.1, canBegin: false, canContinue: false)
        )
        XCTAssertTrue(physicalTail.shouldConsume)

        let physicalEnd = machine.handleScroll(
            input(
                now: 1.2,
                canBegin: false,
                canContinue: false,
                isPhysicalEnd: true
            )
        )
        XCTAssertTrue(physicalEnd.shouldConsume)
        XCTAssertEqual(
            machine.state,
            .draining(generation: 1, deadline: 1.5)
        )

        let momentum = machine.handleScroll(
            input(
                now: 1.3,
                canBegin: false,
                canContinue: false,
                isMomentum: true
            )
        )
        XCTAssertTrue(momentum.shouldConsume)

        let momentumEnd = machine.handleScroll(
            input(
                now: 1.4,
                canBegin: false,
                canContinue: false,
                isMomentum: true,
                isMomentumEnd: true
            )
        )
        XCTAssertTrue(momentumEnd.shouldConsume)
        XCTAssertEqual(machine.state, .idle)
    }

    func testPhysicalEndDrainsMomentumBeforeReturningIdle() {
        var machine = CaptureStateMachine()
        _ = machine.handleScroll(
            input(canBegin: true, canContinue: true, isNew: true)
        )

        let physicalEnd = machine.handleScroll(
            input(
                canBegin: true,
                canContinue: true,
                isPhysicalEnd: true
            )
        )
        XCTAssertEqual(physicalEnd.actions, [.finish(generation: 1)])

        let momentum = machine.handleScroll(
            input(
                now: 0.1,
                canBegin: true,
                canContinue: true,
                isMomentum: true
            )
        )
        XCTAssertTrue(momentum.shouldConsume)
        XCTAssertEqual(
            machine.state,
            .draining(generation: 1, deadline: 5.1)
        )

        let momentumEnd = machine.handleScroll(
            input(
                now: 0.2,
                canBegin: true,
                canContinue: true,
                isMomentum: true,
                isMomentumEnd: true
            )
        )
        XCTAssertTrue(momentumEnd.shouldConsume)
        XCTAssertEqual(machine.state, .idle)
    }

    func testExpiredPhysicalCapturePassesUnmatchedNewGesture() {
        var machine = CaptureStateMachine()
        _ = machine.handleScroll(
            input(canBegin: true, canContinue: true, isNew: true)
        )

        let decision = machine.handleScroll(
            input(
                now: 6,
                canBegin: false,
                canContinue: false,
                isNew: true
            )
        )

        XCTAssertFalse(decision.shouldConsume)
        XCTAssertEqual(decision.actions, [.cancel(generation: 1)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testExpiredPhysicalCaptureStartsFreshMatchingGesture() {
        var machine = CaptureStateMachine()
        _ = machine.handleScroll(
            input(canBegin: true, canContinue: true, isNew: true)
        )

        let decision = machine.handleScroll(
            input(
                now: 6,
                canBegin: true,
                canContinue: true,
                isNew: true
            )
        )

        XCTAssertTrue(decision.shouldConsume)
        XCTAssertEqual(
            decision.actions,
            [
                .cancel(generation: 1),
                .begin(generation: 2),
                .submitDelta(generation: 2),
            ]
        )
        XCTAssertEqual(machine.state, .physical(generation: 2))
    }

    func testExpiredSwallowingCaptureStartsFreshMatchingGesture() {
        var machine = CaptureStateMachine()
        _ = machine.handleScroll(
            input(canBegin: true, canContinue: true, isNew: true)
        )
        _ = machine.stopResizing()

        let decision = machine.handleScroll(
            input(
                now: 6,
                canBegin: true,
                canContinue: true,
                isNew: true
            )
        )

        XCTAssertTrue(decision.shouldConsume)
        XCTAssertEqual(
            decision.actions,
            [
                .cancel(generation: 1),
                .begin(generation: 2),
                .submitDelta(generation: 2),
            ]
        )
        XCTAssertEqual(machine.state, .physical(generation: 2))
    }

    private func input(
        now: TimeInterval = 0,
        canBegin: Bool,
        canContinue: Bool,
        isNew: Bool = false,
        isPhysicalEnd: Bool = false,
        hasPhysicalPhase: Bool = true,
        isMomentum: Bool = false,
        isMomentumEnd: Bool = false
    ) -> CaptureStateMachine.ScrollInput {
        CaptureStateMachine.ScrollInput(
            now: now,
            canBeginCapture: canBegin,
            canContinueResize: canContinue,
            isNewPhysicalSequence: isNew,
            isPhysicalEnd: isPhysicalEnd,
            hasPhysicalPhase: hasPhysicalPhase,
            isMomentum: isMomentum,
            isMomentumEnd: isMomentumEnd
        )
    }
}
