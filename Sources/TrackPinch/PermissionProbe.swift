import AppKit
@preconcurrency import ApplicationServices

enum PermissionProbe {
    struct State {
        let accessibilityTrusted: Bool
    }

    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var state: State {
        State(accessibilityTrusted: accessibilityTrusted)
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func openAccessibilitySettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }
}
