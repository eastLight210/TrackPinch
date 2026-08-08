import AppKit
import Combine
import TrackPinchCore

@MainActor
final class TrackPinchAppModel: ObservableObject {
    enum OperationalState {
        case active
        case paused
        case attention
        case starting
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var sensitivity: Double
    @Published private(set) var modifiers: NSEvent.ModifierFlags
    @Published private(set) var hasPresentedOnboarding: Bool
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var eventTapHealth: EventTapProbe.Health = .stopped
    @Published private(set) var captureState = "Idle"
    @Published private(set) var targetAppName = "None"
    @Published private(set) var lastScrollEvent = "No scroll observed"
    @Published private(set) var lastModifierEvent = "No modifier observed"
    @Published private(set) var liveResizeResult = "Not run"
    @Published private(set) var lastAXResult = "Not run"
    @Published private(set) var lastPermissionAction = "Not requested"

    var onEnabledChanged: ((Bool) -> Void)?
    var onSensitivityChanged: ((Double) -> Void)?
    var onModifiersChanged: ((NSEvent.ModifierFlags) -> Void)?
    var onRequestPermissions: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onRefreshPermissions: (() -> Void)?
    var onRetryEventTap: (() -> Void)?
    var onRunAXProbe: (() -> Void)?
    var onQuit: (() -> Void)?

    private let settingsStore: TrackPinchSettingsStore
    private var settings: TrackPinchSettings

    init(settingsStore: TrackPinchSettingsStore) {
        self.settingsStore = settingsStore
        let settings = settingsStore.load()
        self.settings = settings
        isEnabled = settings.isEnabled
        sensitivity = settings.sensitivity
        modifiers = settings.modifiers
        hasPresentedOnboarding = settings.hasPresentedOnboarding
        hasCompletedOnboarding = settings.hasCompletedOnboarding
    }

    var operationalState: OperationalState {
        guard isEnabled else { return .paused }
        guard accessibilityTrusted else {
            return .attention
        }

        switch eventTapHealth {
        case .running:
            return .active
        case .starting:
            return .starting
        case .stopped, .unavailable, .degraded:
            return .attention
        }
    }

    var statusTitle: String {
        switch operationalState {
        case .active:
            return captureState == "Resizing" ? "Resizing" : "Ready"
        case .paused:
            return "Paused"
        case .attention:
            return accessibilityTrusted
                ? "Input needs attention"
                : "Permissions required"
        case .starting:
            return "Starting…"
        }
    }

    var permissionsReady: Bool {
        accessibilityTrusted
    }

    var modifierGlyphs: String {
        var glyphs: [String] = []
        if modifiers.contains(.function) { glyphs.append("fn") }
        if modifiers.contains(.control) { glyphs.append("⌃") }
        if modifiers.contains(.option) { glyphs.append("⌥") }
        if modifiers.contains(.command) { glyphs.append("⌘") }
        if modifiers.contains(.shift) { glyphs.append("⇧") }
        return glyphs.joined(separator: " ")
    }

    var versionDescription: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "TrackPinchReleaseVersion"
        ) as? String ?? Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
        return "v\(version)"
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        settings.isEnabled = enabled
        persist()
        onEnabledChanged?(enabled)
    }

    func setSensitivity(_ value: Double) {
        let value = TrackPinchSettings.clampedSensitivity(value)
        guard value != sensitivity else { return }
        sensitivity = value
        settings.sensitivity = value
        persist()
        onSensitivityChanged?(value)
    }

    func resetSensitivity() {
        setSensitivity(TrackPinchSettings.defaultSensitivity)
    }

    func markOnboardingPresented() {
        guard !hasPresentedOnboarding else { return }
        hasPresentedOnboarding = true
        settings.hasPresentedOnboarding = true
        persist()
    }

    func completeOnboarding() {
        guard permissionsReady, !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        settings.hasCompletedOnboarding = true
        persist()
    }

    func toggleModifier(_ modifier: NSEvent.ModifierFlags) {
        var updated = modifiers
        if updated.contains(modifier) {
            updated.remove(modifier)
        } else {
            updated.insert(modifier)
        }

        updated = ModifierNormalizer.normalized(updated)
        guard !updated.isEmpty, updated != modifiers else { return }
        modifiers = updated
        settings.modifiers = updated
        persist()
        onModifiersChanged?(updated)
    }

    func updatePermissions(_ state: PermissionProbe.State) {
        accessibilityTrusted = state.accessibilityTrusted
    }

    func updateEventTap(_ snapshot: EventTapProbe.Snapshot) {
        eventTapHealth = snapshot.health
        captureState = snapshot.captureState
        lastScrollEvent = snapshot.lastScrollEvent
        lastModifierEvent = snapshot.lastModifierEvent
    }

    func updateTarget(appName: String) {
        targetAppName = appName
    }

    func updateLiveResize(status: String) {
        liveResizeResult = status
    }

    func updateAXResult(_ result: String) {
        lastAXResult = result
    }

    func updatePermissionAction(_ result: String) {
        lastPermissionAction = result
    }

    func requestPermissions() {
        onRequestPermissions?()
    }

    func openAccessibilitySettings() {
        onOpenAccessibilitySettings?()
    }

    func refreshPermissions() {
        onRefreshPermissions?()
    }

    func retryEventTap() {
        onRetryEventTap?()
    }

    func runAXProbe() {
        onRunAXProbe?()
    }

    func quit() {
        onQuit?()
    }

    private func persist() {
        settingsStore.save(settings)
    }
}
