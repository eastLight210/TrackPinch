import Foundation

public struct CaptureStateMachine: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case physical(generation: UInt64)
        case swallowing(generation: UInt64)
        case draining(generation: UInt64, deadline: TimeInterval)

        public var description: String {
            switch self {
            case .idle:
                return "Idle"
            case .physical:
                return "Resizing"
            case .swallowing:
                return "Swallowing"
            case .draining:
                return "Draining"
            }
        }

        public var generation: UInt64? {
            switch self {
            case .idle:
                return nil
            case .physical(let generation),
                 .swallowing(let generation),
                 .draining(let generation, _):
                return generation
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case begin(generation: UInt64)
        case submitDelta(generation: UInt64)
        case finish(generation: UInt64)
        case cancel(generation: UInt64)
    }

    public struct ScrollInput: Equatable, Sendable {
        public let now: TimeInterval
        public let canBeginCapture: Bool
        public let canContinueResize: Bool
        public let isNewPhysicalSequence: Bool
        public let isPhysicalEnd: Bool
        public let hasPhysicalPhase: Bool
        public let isMomentum: Bool
        public let isMomentumEnd: Bool

        public init(
            now: TimeInterval,
            canBeginCapture: Bool,
            canContinueResize: Bool,
            isNewPhysicalSequence: Bool,
            isPhysicalEnd: Bool,
            hasPhysicalPhase: Bool,
            isMomentum: Bool,
            isMomentumEnd: Bool
        ) {
            self.now = now
            self.canBeginCapture = canBeginCapture
            self.canContinueResize = canContinueResize
            self.isNewPhysicalSequence = isNewPhysicalSequence
            self.isPhysicalEnd = isPhysicalEnd
            self.hasPhysicalPhase = hasPhysicalPhase
            self.isMomentum = isMomentum
            self.isMomentumEnd = isMomentumEnd
        }
    }

    public struct Decision: Equatable, Sendable {
        public let shouldConsume: Bool
        public let actions: [Action]

        public init(shouldConsume: Bool, actions: [Action] = []) {
            self.shouldConsume = shouldConsume
            self.actions = actions
        }
    }

    public private(set) var state: State = .idle
    private var nextGeneration: UInt64 = 0
    private var ownedEventDeadline: TimeInterval?

    public init() {}

    public mutating func handleScroll(_ input: ScrollInput) -> Decision {
        if let expirationActions = expireOwnedCaptureIfNeeded(at: input.now) {
            let idleDecision = handleIdle(input)
            return Decision(
                shouldConsume: idleDecision.shouldConsume,
                actions: expirationActions + idleDecision.actions
            )
        }

        switch state {
        case .idle:
            return handleIdle(input)

        case .physical(let generation):
            guard input.canContinueResize else {
                state = input.isPhysicalEnd
                    ? .draining(generation: generation, deadline: input.now + 0.3)
                    : .swallowing(generation: generation)
                ownedEventDeadline = input.isPhysicalEnd
                    ? nil
                    : input.now + 5
                return Decision(
                    shouldConsume: true,
                    actions: [.cancel(generation: generation)]
                )
            }

            if input.isPhysicalEnd {
                state = .draining(
                    generation: generation,
                    deadline: input.now + 0.3
                )
                ownedEventDeadline = nil
                return Decision(
                    shouldConsume: true,
                    actions: [.finish(generation: generation)]
                )
            }

            ownedEventDeadline = input.now + 5
            let actions: [Action] = !input.isMomentum && input.hasPhysicalPhase
                ? [.submitDelta(generation: generation)]
                : []
            return Decision(shouldConsume: true, actions: actions)

        case .swallowing(let generation):
            if input.isPhysicalEnd {
                state = .draining(
                    generation: generation,
                    deadline: input.now + 0.3
                )
                ownedEventDeadline = nil
            } else {
                ownedEventDeadline = input.now + 5
            }
            return Decision(shouldConsume: true)

        case .draining(let generation, _):
            if input.isMomentum {
                if input.isMomentumEnd {
                    state = .idle
                } else {
                    state = .draining(
                        generation: generation,
                        deadline: input.now + 5
                    )
                }
                ownedEventDeadline = nil
                return Decision(shouldConsume: true)
            }

            if input.isNewPhysicalSequence {
                guard input.canBeginCapture else {
                    state = .idle
                    ownedEventDeadline = nil
                    return Decision(shouldConsume: false)
                }
                return beginCapture(
                    at: input.now,
                    shouldSubmitDelta: input.hasPhysicalPhase
                )
            }

            return Decision(shouldConsume: true)
        }
    }

    @discardableResult
    public mutating func stopResizing(
        at now: TimeInterval? = nil
    ) -> Action? {
        guard case .physical(let generation) = state else { return nil }
        state = .swallowing(generation: generation)
        if let now {
            ownedEventDeadline = now + 5
        }
        return .cancel(generation: generation)
    }

    @discardableResult
    public mutating func cancelCapture() -> Action? {
        guard let generation = state.generation else { return nil }
        state = .idle
        ownedEventDeadline = nil
        return .cancel(generation: generation)
    }

    private mutating func handleIdle(_ input: ScrollInput) -> Decision {
        guard input.canBeginCapture else {
            return Decision(shouldConsume: false)
        }
        return beginCapture(
            at: input.now,
            shouldSubmitDelta: input.hasPhysicalPhase
        )
    }

    private mutating func expireOwnedCaptureIfNeeded(
        at now: TimeInterval
    ) -> [Action]? {
        switch state {
        case .physical(let generation), .swallowing(let generation):
            guard let ownedEventDeadline, now >= ownedEventDeadline else {
                return nil
            }
            state = .idle
            self.ownedEventDeadline = nil
            return [.cancel(generation: generation)]

        case .draining(_, let deadline):
            guard now >= deadline else { return nil }
            state = .idle
            ownedEventDeadline = nil
            return []

        case .idle:
            return nil
        }
    }

    private mutating func beginCapture(
        at now: TimeInterval,
        shouldSubmitDelta: Bool
    ) -> Decision {
        nextGeneration &+= 1
        let generation = nextGeneration
        state = .physical(generation: generation)
        ownedEventDeadline = now + 5

        var actions: [Action] = [.begin(generation: generation)]
        if shouldSubmitDelta {
            actions.append(.submitDelta(generation: generation))
        }
        return Decision(shouldConsume: true, actions: actions)
    }
}
