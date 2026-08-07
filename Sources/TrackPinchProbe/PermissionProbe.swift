import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

enum PermissionProbe {
    struct State {
        let accessibilityTrusted: Bool
        let inputListeningGranted: Bool
    }

    enum SettingsPane: String {
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
    }

    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var inputListeningGranted: Bool {
        CGPreflightListenEventAccess()
    }

    static var state: State {
        State(
            accessibilityTrusted: accessibilityTrusted,
            inputListeningGranted: inputListeningGranted
        )
    }

    @discardableResult
    static func request() -> State {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary

        _ = AXIsProcessTrustedWithOptions(options)
        _ = CGRequestListenEventAccess()
        return state
    }

    @discardableResult
    static func openSettings(_ pane: SettingsPane) -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)"
        ) else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }

    static func nextMissingPane(for state: State) -> SettingsPane? {
        if !state.accessibilityTrusted {
            return .accessibility
        }
        if !state.inputListeningGranted {
            return .inputMonitoring
        }
        return nil
    }
}
