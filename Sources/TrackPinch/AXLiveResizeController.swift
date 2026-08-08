import ApplicationServices
import CoreGraphics
import Foundation
import OSLog
import TrackPinchCore

final class AXLiveResizeController: @unchecked Sendable {
    typealias StatusHandler = @MainActor @Sendable (String) -> Void

    private struct Session {
        let generation: UInt64
        let window: AXUIElement
        var actualSize: CGSize
        var interpreter: ResizeGestureInterpreter
        var pendingSizeDelta = CGSize.zero
        var applyScheduled = false
    }

    private enum ResolutionError: Error, CustomStringConvertible {
        case accessibilityDenied
        case missingWindow
        case unsupportedRole
        case unsupportedSubrole
        case minimized
        case unreadableGeometry
        case sizeNotSettable(AXError)
        case invalidSize

        var description: String {
            switch self {
            case .accessibilityDenied:
                return "Accessibility permission is not granted"
            case .missingWindow:
                return "No focused or main window"
            case .unsupportedRole:
                return "Focused element is not an AX window"
            case .unsupportedSubrole:
                return "Window is not an AXStandardWindow"
            case .minimized:
                return "Window is minimized"
            case .unreadableGeometry:
                return "Could not read AX position and size"
            case .sizeNotSettable(let error):
                return "AXSize is not settable (\(error.rawValue))"
            case .invalidSize:
                return "Window reported an invalid size"
            }
        }
    }

    private let queue = DispatchQueue(
        label: "dev.badgerworks.trackpinch.ax-live-resize",
        qos: .userInteractive
    )
    private let logger = Logger(
        subsystem: "dev.badgerworks.trackpinch",
        category: "ax-live-resize"
    )
    private let callbackLock = NSLock()

    private var activeGeneration: UInt64?
    private var session: Session?
    private var sensitivity: Double = TrackPinchSettings.defaultSensitivity
    private var lastStatusPublishTime: TimeInterval = 0
    private var onStatusStorage: StatusHandler?

    var onStatus: StatusHandler? {
        get { callbackLock.withLock { onStatusStorage } }
        set { callbackLock.withLock { onStatusStorage = newValue } }
    }

    func begin(generation: UInt64, pid: pid_t) {
        queue.async { [weak self] in
            self?.beginOnQueue(generation: generation, pid: pid)
        }
    }

    func setSensitivity(_ sensitivity: Double) {
        let sensitivity = TrackPinchSettings.clampedSensitivity(sensitivity)
        queue.async { [weak self] in
            self?.sensitivity = sensitivity
        }
    }

    func submit(fingerDelta: CGPoint, generation: UInt64) {
        queue.async { [weak self] in
            self?.submitOnQueue(
                fingerDelta: fingerDelta,
                generation: generation
            )
        }
    }

    func finish(generation: UInt64) {
        queue.async { [weak self] in
            self?.finishOnQueue(generation: generation)
        }
    }

    func cancel(generation: UInt64, reason: String) {
        queue.async { [weak self] in
            guard let self, self.activeGeneration == generation else {
                return
            }
            self.activeGeneration = nil
            self.session = nil
            self.publish("Cancelled: \(reason)", level: .info)
        }
    }

    private func beginOnQueue(generation: UInt64, pid: pid_t) {
        activeGeneration = generation
        session = nil
        publish("Resolving target PID \(pid)", level: .debug)

        do {
            let target = try Self.resolveTarget(pid: pid)
            guard activeGeneration == generation else { return }

            session = Session(
                generation: generation,
                window: target.window,
                actualSize: target.size,
                interpreter: ResizeGestureInterpreter(
                    horizontalSensitivity: sensitivity,
                    verticalSensitivity: sensitivity
                )
            )
            publish(
                String(
                    format: "Ready %.0fx%.0f for PID %d",
                    target.size.width,
                    target.size.height,
                    pid
                ),
                level: .info
            )
        } catch {
            guard activeGeneration == generation else { return }
            activeGeneration = nil
            session = nil
            publish("Unsupported target: \(error)", level: .error)
        }
    }

    private func submitOnQueue(
        fingerDelta: CGPoint,
        generation: UInt64
    ) {
        guard activeGeneration == generation, var session else { return }

        let previousMode = session.interpreter.mode
        let sizeDelta = session.interpreter.ingest(fingerDelta)
        let currentMode = session.interpreter.mode

        if previousMode == nil, let currentMode {
            publish("Mode locked: \(currentMode.rawValue)", level: .info)
        }

        guard let sizeDelta else {
            self.session = session
            return
        }

        session.pendingSizeDelta.width += sizeDelta.width
        session.pendingSizeDelta.height += sizeDelta.height

        let shouldSchedule = !session.applyScheduled
        session.applyScheduled = true
        self.session = session

        if shouldSchedule {
            queue.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
                self?.applyPendingOnQueue(generation: generation)
            }
        }
    }

    private func finishOnQueue(generation: UInt64) {
        guard activeGeneration == generation else { return }

        applyPendingOnQueue(generation: generation)
        guard activeGeneration == generation else { return }

        let completion: String
        if let session {
            completion = String(
                format: "Completed %@ at %.0fx%.0f",
                session.interpreter.mode?.rawValue ?? "unclassified",
                session.actualSize.width,
                session.actualSize.height
            )
        } else {
            completion = "Completed without an eligible target"
        }

        activeGeneration = nil
        session = nil
        publish(completion, level: .info)
    }

    private func applyPendingOnQueue(generation: UInt64) {
        guard activeGeneration == generation, var session else { return }

        session.applyScheduled = false
        let delta = session.pendingSizeDelta
        session.pendingSizeDelta = .zero

        guard abs(delta.width) >= 0.01 || abs(delta.height) >= 0.01 else {
            self.session = session
            return
        }

        var requestedSize = CGSize(
            width: min(max(session.actualSize.width + delta.width, 160), 16_384),
            height: min(max(session.actualSize.height + delta.height, 120), 16_384)
        )
        guard let requestedValue = AXValueCreate(.cgSize, &requestedSize) else {
            fail(generation: generation, message: "Could not create AX size value")
            return
        }

        let setError = AXUIElementSetAttributeValue(
            session.window,
            kAXSizeAttribute as CFString,
            requestedValue
        )
        guard setError == .success else {
            fail(
                generation: generation,
                message: "AX size write failed (\(setError.rawValue))"
            )
            return
        }

        guard let appliedSize = Self.sizeAttribute(of: session.window) else {
            fail(generation: generation, message: "AX size readback failed")
            return
        }

        session.actualSize = appliedSize
        self.session = session

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastStatusPublishTime >= 0.1 {
            lastStatusPublishTime = now
            publish(
                String(
                    format: "%@ %.0fx%.0f",
                    session.interpreter.mode?.rawValue ?? "unclassified",
                    appliedSize.width,
                    appliedSize.height
                ),
                level: .debug
            )
        }
    }

    private func fail(generation: UInt64, message: String) {
        guard activeGeneration == generation else { return }
        activeGeneration = nil
        session = nil
        publish("Resize stopped: \(message)", level: .error)
    }

    private func publish(_ message: String, level: OSLogType) {
        logger.log(level: level, "\(message, privacy: .public)")
        let callback = callbackLock.withLock { onStatusStorage }
        guard let callback else { return }
        Task { @MainActor in
            callback(message)
        }
    }

    private static func resolveTarget(
        pid: pid_t
    ) throws -> (window: AXUIElement, size: CGSize) {
        guard AXIsProcessTrusted() else {
            throw ResolutionError.accessibilityDenied
        }

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)

        guard let window = focusedOrMainWindow(of: application) else {
            throw ResolutionError.missingWindow
        }
        guard stringAttribute(kAXRoleAttribute as CFString, of: window)
            == kAXWindowRole else {
            throw ResolutionError.unsupportedRole
        }
        guard stringAttribute(kAXSubroleAttribute as CFString, of: window)
            == kAXStandardWindowSubrole else {
            throw ResolutionError.unsupportedSubrole
        }
        guard boolAttribute(kAXMinimizedAttribute as CFString, of: window)
            != true else {
            throw ResolutionError.minimized
        }
        guard positionAttribute(of: window) != nil,
              let size = sizeAttribute(of: window) else {
            throw ResolutionError.unreadableGeometry
        }

        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(
            window,
            kAXSizeAttribute as CFString,
            &settable
        )
        guard settableError == .success, settable.boolValue else {
            throw ResolutionError.sizeNotSettable(settableError)
        }
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            throw ResolutionError.invalidSize
        }

        return (window, size)
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
        guard AXUIElementCopyAttributeValue(element, attribute, &value)
            == .success else {
            return nil
        }
        return value as? String
    }

    private static func boolAttribute(
        _ attribute: CFString,
        of element: AXUIElement
    ) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value)
            == .success else {
            return nil
        }
        return value as? Bool
    }

    private static func positionAttribute(of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private static func sizeAttribute(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
