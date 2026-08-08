public enum TrackPinchOperationGate {
    public static func allowsCapture(
        userEnabled: Bool,
        accessibilityTrusted: Bool,
        eventTapHealthy: Bool
    ) -> Bool {
        userEnabled
            && accessibilityTrusted
            && eventTapHealthy
    }
}
