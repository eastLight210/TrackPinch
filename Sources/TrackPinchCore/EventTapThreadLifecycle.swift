public struct EventTapThreadLifecycle: Sendable {
    public enum Command: Equatable, Sendable {
        case none
        case startThread
        case stopThread
    }

    public private(set) var hasThread = false
    public private(set) var stopRequested = false
    public private(set) var restartRequested = false

    public init() {}

    public mutating func requestStart() -> Command {
        guard !hasThread else { return .none }
        hasThread = true
        stopRequested = false
        restartRequested = false
        return .startThread
    }

    public mutating func requestRetry() -> Command {
        guard hasThread else { return requestStart() }
        stopRequested = true
        restartRequested = true
        return .stopThread
    }

    public mutating func requestStop() -> Command {
        restartRequested = false
        guard hasThread else {
            stopRequested = false
            return .none
        }
        stopRequested = true
        return .stopThread
    }

    public mutating func threadDidStop() -> Command {
        hasThread = false
        stopRequested = false

        guard restartRequested else { return .none }
        restartRequested = false
        hasThread = true
        return .startThread
    }
}
