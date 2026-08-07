import CoreGraphics

public enum ScrollDeltaNormalizer {
    public static func deviceIndependent(
        x: CGFloat,
        y: CGFloat,
        isDirectionInvertedFromDevice: Bool
    ) -> CGPoint {
        // NSEvent reports content-scroll direction. Convert it to finger movement
        // while compensating for the user's Natural Scrolling setting.
        let factor: CGFloat = isDirectionInvertedFromDevice ? 1 : -1
        return CGPoint(x: x * factor, y: y * factor)
    }
}
