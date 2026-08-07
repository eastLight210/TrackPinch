import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

final class AXResizeProbe {
    struct Result {
        let message: String
        let succeeded: Bool
    }

    private let queue = DispatchQueue(
        label: "dev.badgerworks.trackpinch.ax-probe",
        qos: .userInitiated
    )
    private let logger = Logger(
        subsystem: "dev.badgerworks.trackpinch",
        category: "ax-resize-probe"
    )

    func run(
        pid: pid_t,
        completion: @escaping (Result) -> Void
    ) {
        queue.async { [logger] in
            let result = Self.perform(pid: pid, logger: logger)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static func perform(
        pid: pid_t,
        logger: Logger
    ) -> Result {
        guard AXIsProcessTrusted() else {
            return Result(
                message: "Accessibility permission is not granted",
                succeeded: false
            )
        }

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)

        guard let window = focusedOrMainWindow(of: application) else {
            return Result(
                message: "No focused or main AX window for PID \(pid)",
                succeeded: false
            )
        }

        guard stringAttribute(kAXRoleAttribute as CFString, of: window) == kAXWindowRole else {
            return Result(message: "Focused element is not an AX window", succeeded: false)
        }

        guard stringAttribute(kAXSubroleAttribute as CFString, of: window) == kAXStandardWindowSubrole else {
            return Result(message: "Window is not an AXStandardWindow", succeeded: false)
        }

        if boolAttribute(kAXMinimizedAttribute as CFString, of: window) == true {
            return Result(message: "Window is minimized", succeeded: false)
        }

        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            window,
            kAXSizeAttribute as CFString,
            &settable
        )
        guard settableError == .success, settable.boolValue else {
            return Result(
                message: "AXSize is not settable (\(settableError.rawValue))",
                succeeded: false
            )
        }

        guard let originalSize = sizeAttribute(of: window) else {
            return Result(message: "Could not read original AXSize", succeeded: false)
        }

        var requestedSize = CGSize(
            width: min(originalSize.width + 20, 16_384),
            height: min(originalSize.height + 20, 16_384)
        )
        guard let requestedValue = AXValueCreate(.cgSize, &requestedSize) else {
            return Result(message: "Could not create AX size value", succeeded: false)
        }

        let setError = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            requestedValue
        )
        guard setError == .success else {
            return Result(
                message: "AX size write failed (\(setError.rawValue))",
                succeeded: false
            )
        }

        let appliedSize = sizeAttribute(of: window)
        Thread.sleep(forTimeInterval: 0.4)

        var restoreSize = originalSize
        let restoreValue = AXValueCreate(.cgSize, &restoreSize)
        let restoreError: AXError
        if let restoreValue {
            restoreError = AXUIElementSetAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                restoreValue
            )
        } else {
            restoreError = .failure
        }

        let appliedDescription: String
        if let appliedSize {
            appliedDescription = String(
                format: "%.0fx%.0f",
                appliedSize.width,
                appliedSize.height
            )
        } else {
            appliedDescription = "unreadable"
        }

        let message = String(
            format: "requested %.0fx%.0f, applied %@, restore=%d",
            requestedSize.width,
            requestedSize.height,
            appliedDescription,
            restoreError.rawValue
        )
        logger.info("\(message, privacy: .public)")

        return Result(
            message: message,
            succeeded: restoreError == .success && appliedSize != nil
        )
    }

    private static func focusedOrMainWindow(
        of application: AXUIElement
    ) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(
                application,
                attribute as CFString,
                &value
            )
            if error == .success,
               let value,
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                return unsafeBitCast(value, to: AXUIElement.self)
            }
        }
        return nil
    }

    private static func stringAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func boolAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private static func sizeAttribute(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSizeAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
