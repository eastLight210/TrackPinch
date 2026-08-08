import CoreGraphics

public enum PopoverSizePolicy {
    public static let width: CGFloat = 370
    public static let idealHeight: CGFloat = 560
    public static let verticalSafetyMargin: CGFloat = 24

    public static func contentHeight(
        forVisibleFrameHeight visibleFrameHeight: CGFloat
    ) -> CGFloat {
        guard visibleFrameHeight.isFinite, visibleFrameHeight > 0 else {
            return idealHeight
        }

        let availableHeight = max(
            1,
            visibleFrameHeight - verticalSafetyMargin
        )
        return min(idealHeight, availableHeight)
    }
}
