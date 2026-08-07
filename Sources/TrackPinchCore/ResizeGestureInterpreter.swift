import CoreGraphics

public enum ResizeGestureMode: String, Equatable, Sendable {
    case horizontal
    case vertical
    case diagonal
}

public struct ResizeGestureInterpreter: Sendable {
    public let deadZone: CGFloat
    public let axisLockRatio: CGFloat
    public let horizontalSensitivity: CGFloat
    public let verticalSensitivity: CGFloat

    public private(set) var mode: ResizeGestureMode?
    private var accumulated = CGPoint.zero

    public init(
        deadZone: CGFloat = 8,
        axisLockRatio: CGFloat = 1.5,
        horizontalSensitivity: CGFloat = 1,
        verticalSensitivity: CGFloat = 1
    ) {
        self.deadZone = deadZone
        self.axisLockRatio = axisLockRatio
        self.horizontalSensitivity = horizontalSensitivity
        self.verticalSensitivity = verticalSensitivity
    }

    public mutating func ingest(_ fingerDelta: CGPoint) -> CGSize? {
        guard fingerDelta.x.isFinite, fingerDelta.y.isFinite else {
            return nil
        }

        if mode == nil {
            accumulated.x += fingerDelta.x
            accumulated.y += fingerDelta.y

            guard hypot(accumulated.x, accumulated.y) >= deadZone else {
                return nil
            }

            let absoluteX = abs(accumulated.x)
            let absoluteY = abs(accumulated.y)
            if absoluteX >= axisLockRatio * absoluteY {
                mode = .horizontal
            } else if absoluteY >= axisLockRatio * absoluteX {
                mode = .vertical
            } else {
                mode = .diagonal
            }

            // The movement used to classify the gesture is intentionally not
            // applied to the window, avoiding a jump when the mode locks.
            accumulated = .zero
            return nil
        }

        switch mode {
        case .horizontal:
            return CGSize(
                width: fingerDelta.x * horizontalSensitivity,
                height: 0
            )
        case .vertical:
            return CGSize(
                width: 0,
                height: fingerDelta.y * verticalSensitivity
            )
        case .diagonal:
            return CGSize(
                width: fingerDelta.x * horizontalSensitivity,
                height: fingerDelta.y * verticalSensitivity
            )
        case nil:
            return nil
        }
    }
}
