import AppKit

public enum ModifierNormalizer {
    public static let defaultGestureModifiers: NSEvent.ModifierFlags = [
        .control,
        .option,
        .command,
    ]

    public static let supported: NSEvent.ModifierFlags = [
        .function,
        .control,
        .option,
        .command,
        .shift,
    ]

    public static func normalized(
        _ flags: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        flags.intersection(supported)
    }

    public static func matches(
        _ flags: NSEvent.ModifierFlags,
        configured: NSEvent.ModifierFlags
    ) -> Bool {
        normalized(flags) == normalized(configured)
    }

    public static func description(
        of flags: NSEvent.ModifierFlags
    ) -> String {
        let normalizedFlags = normalized(flags)
        var names: [String] = []

        if normalizedFlags.contains(.function) { names.append("Fn") }
        if normalizedFlags.contains(.control) { names.append("Control") }
        if normalizedFlags.contains(.option) { names.append("Option") }
        if normalizedFlags.contains(.command) { names.append("Command") }
        if normalizedFlags.contains(.shift) { names.append("Shift") }

        return names.isEmpty ? "None" : names.joined(separator: "+")
    }
}
