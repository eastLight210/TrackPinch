import AppKit
import Foundation

public struct TrackPinchSettings: Equatable {
    public static let defaultSensitivity = 1.0
    public static let sensitivityRange = 0.5 ... 3.0

    public var isEnabled: Bool
    public var sensitivity: Double
    public var modifiers: NSEvent.ModifierFlags

    public init(
        isEnabled: Bool = true,
        sensitivity: Double = defaultSensitivity,
        modifiers: NSEvent.ModifierFlags = ModifierNormalizer.defaultGestureModifiers
    ) {
        self.isEnabled = isEnabled
        self.sensitivity = Self.clampedSensitivity(sensitivity)
        self.modifiers = Self.validModifiers(modifiers)
    }

    public static func clampedSensitivity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultSensitivity }
        return min(max(value, sensitivityRange.lowerBound), sensitivityRange.upperBound)
    }

    public static func validModifiers(
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        let normalized = ModifierNormalizer.normalized(modifiers)
        return normalized.isEmpty
            ? ModifierNormalizer.defaultGestureModifiers
            : normalized
    }
}

public final class TrackPinchSettingsStore {
    private enum Key {
        static let isEnabled = "settings.isEnabled"
        static let sensitivity = "settings.sensitivity"
        static let modifiers = "settings.modifiers"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> TrackPinchSettings {
        let isEnabled = defaults.object(forKey: Key.isEnabled) == nil
            ? true
            : defaults.bool(forKey: Key.isEnabled)
        let sensitivity = defaults.object(forKey: Key.sensitivity) == nil
            ? TrackPinchSettings.defaultSensitivity
            : defaults.double(forKey: Key.sensitivity)

        let modifiers: NSEvent.ModifierFlags
        if defaults.object(forKey: Key.modifiers) == nil {
            modifiers = ModifierNormalizer.defaultGestureModifiers
        } else {
            modifiers = NSEvent.ModifierFlags(
                rawValue: UInt(defaults.integer(forKey: Key.modifiers))
            )
        }

        return TrackPinchSettings(
            isEnabled: isEnabled,
            sensitivity: sensitivity,
            modifiers: modifiers
        )
    }

    public func save(_ settings: TrackPinchSettings) {
        let normalized = TrackPinchSettings(
            isEnabled: settings.isEnabled,
            sensitivity: settings.sensitivity,
            modifiers: settings.modifiers
        )
        defaults.set(normalized.isEnabled, forKey: Key.isEnabled)
        defaults.set(normalized.sensitivity, forKey: Key.sensitivity)
        defaults.set(Int(normalized.modifiers.rawValue), forKey: Key.modifiers)
    }
}
