public enum TrackPinchOperationGate {
    public static func allowsCapture(
        userEnabled: Bool,
        accessibilityTrusted: Bool,
        inputListeningGranted: Bool,
        eventTapHealthy: Bool
    ) -> Bool {
        userEnabled
            && accessibilityTrusted
            && inputListeningGranted
            && eventTapHealthy
    }
}
