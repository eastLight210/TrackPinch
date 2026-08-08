import AppKit
import CoreGraphics
import Foundation
import OSLog
import TrackPinchCore

private func trackPinchEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let probe = Unmanaged<EventTapProbe>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return probe.handle(type: type, event: event)
}

final class EventTapProbe: @unchecked Sendable {
    enum Health: Equatable, Sendable {
        case stopped
        case starting
        case running
        case unavailable(String)
        case degraded(String)

        var description: String {
            switch self {
            case .stopped:
                return "Stopped"
            case .starting:
                return "Starting"
            case .running:
                return "Running"
            case .unavailable(let reason):
                return "Unavailable: \(reason)"
            case .degraded(let reason):
                return "Degraded: \(reason)"
            }
        }
    }

    struct Snapshot: Sendable {
        let health: Health
        let suppressionEnabled: Bool
        let captureState: String
        let lastScrollEvent: String
        let lastModifierEvent: String
    }

    typealias SnapshotHandler = @MainActor @Sendable (Snapshot) -> Void

    private let logger = Logger(
        subsystem: "dev.badgerworks.trackpinch",
        category: "event-tap-probe"
    )
    private let resizeController: AXLiveResizeController
    private let lock = NSLock()

    private var eventTap: CFMachPort?
    private var eventTapRunLoop: CFRunLoop?
    private var eventTapThread: Thread?
    private var threadLifecycle = EventTapThreadLifecycle()
    private var health: Health = .stopped
    private var suppressionEnabled = false
    private var accessibilityTrusted = false
    private var configuredModifiers = ModifierNormalizer.defaultGestureModifiers
    private var lastScrollEvent = "No scroll observed"
    private var lastModifierEvent = "No modifier observed"
    private var publishedCaptureState = "Idle"
    private var onSnapshotStorage: SnapshotHandler?
    private var lastPublishedAt: TimeInterval = 0
    private var targetPID: pid_t?

    // Accessed only on the dedicated event-tap thread.
    private var captureStateMachine = CaptureStateMachine()
    private var timeoutDisableTimestamps: [TimeInterval] = []

    init(resizeController: AXLiveResizeController) {
        self.resizeController = resizeController
    }

    var onSnapshot: SnapshotHandler? {
        get {
            lock.withLock { onSnapshotStorage }
        }
        set {
            lock.withLock { onSnapshotStorage = newValue }
        }
    }

    func start() {
        let thread: Thread? = lock.withLock {
            guard threadLifecycle.requestStart() == .startThread else {
                return nil
            }
            return makeEventTapThreadLocked()
        }

        publish(force: true)
        thread?.start()
    }

    func retry() {
        let transition: (Thread?, Bool) = lock.withLock {
            switch threadLifecycle.requestRetry() {
            case .startThread:
                return (makeEventTapThreadLocked(), false)
            case .stopThread:
                return (nil, true)
            case .none:
                return (nil, false)
            }
        }

        publish(force: true)
        if transition.1 {
            requestCurrentThreadStop()
        }
        transition.0?.start()
    }

    func stop() {
        let shouldStop = lock.withLock {
            threadLifecycle.requestStop() == .stopThread
        }
        if shouldStop {
            requestCurrentThreadStop()
        }
    }

    private func requestCurrentThreadStop() {
        let resources: (CFRunLoop?, CFMachPort?) = lock.withLock {
            (eventTapRunLoop, eventTap)
        }

        if let runLoop = resources.0 {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                if let tap = resources.1 {
                    CFMachPortInvalidate(tap)
                }
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    func setSuppressionEnabled(_ enabled: Bool) {
        lock.withLock {
            suppressionEnabled = enabled
        }
        if !enabled {
            scheduleResizeStop(reason: "TrackPinch disabled")
        }
        logger.info("User enabled=\(enabled, privacy: .public)")
        publish(force: true)
    }

    func setAccessibilityTrusted(_ accessibilityTrusted: Bool) {
        lock.withLock {
            self.accessibilityTrusted = accessibilityTrusted
        }
        if !accessibilityTrusted {
            scheduleResizeStop(reason: "Required permission unavailable")
        }
        publish(force: true)
    }

    func setConfiguredModifiers(_ modifiers: NSEvent.ModifierFlags) {
        let modifiers = TrackPinchSettings.validModifiers(modifiers)
        lock.withLock {
            configuredModifiers = modifiers
        }
        logger.info(
            "Configured modifiers=\(ModifierNormalizer.description(of: modifiers), privacy: .public)"
        )
        publish(force: true)
    }

    func setTargetPID(_ pid: pid_t?) {
        lock.withLock {
            targetPID = pid
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                health: health,
                suppressionEnabled: suppressionEnabled,
                captureState: publishedCaptureState,
                lastScrollEvent: lastScrollEvent,
                lastModifierEvent: lastModifierEvent
            )
        }
    }

    fileprivate func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout {
            handleTimeoutDisable()
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByUserInput {
            cancelActiveResize(reason: "event tap disabled by user input")
            updateHealth(.degraded("Disabled by user input"))
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            handleModifierChange(nsEvent.modifierFlags)
            return Unmanaged.passUnretained(event)

        case .scrollWheel:
            let shouldConsume = handleScroll(nsEvent)
            return shouldConsume ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // Caller must hold `lock` and reserve a lifecycle start first.
    private func makeEventTapThreadLocked() -> Thread {
        health = .starting
        let thread = Thread { [weak self] in
            self?.installAndRun()
        }
        thread.name = "TrackPinch Event Tap"
        thread.qualityOfService = .userInteractive
        eventTapThread = thread
        return thread
    }

    private func installAndRun() {
        let eventMask = CGEventMask(
            (1 << CGEventType.scrollWheel.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
        )

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: trackPinchEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lock.withLock {
                health = .unavailable("CGEvent.tapCreate returned nil")
            }
            finishEventTapThread(preserveDiagnostic: true)
            return
        }

        let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        )
        let runLoop = CFRunLoopGetCurrent()

        let shouldStopBeforeEnable = lock.withLock {
            eventTap = tap
            eventTapRunLoop = runLoop
            return threadLifecycle.stopRequested
        }
        if shouldStopBeforeEnable {
            CFMachPortInvalidate(tap)
            finishEventTapThread(preserveDiagnostic: false)
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        if lock.withLock({ threadLifecycle.stopRequested }) {
            CFMachPortInvalidate(tap)
            finishEventTapThread(preserveDiagnostic: false)
            return
        }
        guard CGEvent.tapIsEnabled(tap: tap) else {
            lock.withLock {
                health = .unavailable("CGEvent tap could not be enabled")
            }
            CFMachPortInvalidate(tap)
            finishEventTapThread(preserveDiagnostic: true)
            return
        }

        CFRunLoopAddSource(runLoop, source, .commonModes)
        let shouldStopBeforeRun = lock.withLock {
            if threadLifecycle.stopRequested {
                return true
            }
            health = .running
            return false
        }
        if shouldStopBeforeRun {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            finishEventTapThread(preserveDiagnostic: false)
            return
        }

        publish(force: true)
        logger.info("Active session event tap installed")
        CFRunLoopRun()

        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(tap)
        cancelActiveResize(reason: "event tap stopped")
        finishEventTapThread(preserveDiagnostic: false)
    }

    private func finishEventTapThread(preserveDiagnostic: Bool) {
        let nextThread: Thread? = lock.withLock {
            eventTap = nil
            eventTapRunLoop = nil
            eventTapThread = nil

            if threadLifecycle.threadDidStop() == .startThread {
                return makeEventTapThreadLocked()
            }

            if !preserveDiagnostic {
                if case .degraded = health {
                    // Preserve the diagnostic until an explicit retry.
                } else {
                    health = .stopped
                }
            }
            return nil
        }

        publish(force: true)
        nextThread?.start()
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let phase = event.phase
        let momentumPhase = event.momentumPhase
        let isMomentum = !momentumPhase.isEmpty
        let isNewPhysicalSequence = phase.contains(.mayBegin)
            || phase.contains(.began)
        let isPhysicalEnd = phase.contains(.ended)
            || phase.contains(.cancelled)
        let isMomentumEnd = momentumPhase.contains(.ended)
            || momentumPhase.contains(.cancelled)
        let sessionModifierFlags = NSEvent.ModifierFlags(
            rawValue: UInt(
                CGEventSource.flagsState(.combinedSessionState).rawValue
            )
        )
        let effectiveModifierFlags = event.modifierFlags.union(
            sessionModifierFlags
        )
        let configuration = lock.withLock {
            (
                suppressionEnabled,
                accessibilityTrusted,
                targetPID,
                configuredModifiers,
                health
            )
        }
        let isConfiguredModifier = ModifierNormalizer.matches(
            effectiveModifierFlags,
            configured: configuration.3
        )
        let suppressionIsEnabled = configuration.0
        let candidatePID = configuration.2
        let runtimeIsOperational = TrackPinchOperationGate.allowsCapture(
            userEnabled: suppressionIsEnabled,
            accessibilityTrusted: configuration.1,
            eventTapHealthy: configuration.4 == .running
        )
        let canBeginCapture = runtimeIsOperational
            && isConfiguredModifier
            && event.hasPreciseScrollingDeltas
            && !isMomentum
            && isNewPhysicalSequence
            && candidatePID != nil
        let decision = captureStateMachine.handleScroll(
            CaptureStateMachine.ScrollInput(
                now: now,
                canBeginCapture: canBeginCapture,
                canContinueResize: runtimeIsOperational
                    && isConfiguredModifier,
                isNewPhysicalSequence: isNewPhysicalSequence,
                isPhysicalEnd: isPhysicalEnd,
                hasPhysicalPhase: !phase.isEmpty,
                isMomentum: isMomentum,
                isMomentumEnd: isMomentumEnd
            )
        )
        syncPublishedCaptureState()

        var deltaGeneration: UInt64?
        for action in decision.actions {
            switch action {
            case .begin(let generation):
                guard let candidatePID else { continue }
                resizeController.begin(
                    generation: generation,
                    pid: candidatePID
                )
            case .submitDelta(let generation):
                deltaGeneration = generation
            case .finish(let generation):
                resizeController.finish(generation: generation)
            case .cancel(let generation):
                let reason = runtimeIsOperational
                    ? "modifier chord released"
                    : "TrackPinch became unavailable"
                resizeController.cancel(
                    generation: generation,
                    reason: reason
                )
            }
        }

        let normalizedDelta = ScrollDeltaNormalizer.deviceIndependent(
            x: event.scrollingDeltaX,
            y: event.scrollingDeltaY,
            isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
        )
        let decisionDescription = decision.shouldConsume ? "consume" : "pass"
        let summary = String(
            format: "dx=%+.2f dy=%+.2f precise=%@ phase=%@ momentum=%@ flags=%@ eventFlags=%@ sessionFlags=%@ suppression=%@ -> %@",
            normalizedDelta.x,
            normalizedDelta.y,
            event.hasPreciseScrollingDeltas ? "yes" : "no",
            phaseDescription(phase),
            phaseDescription(momentumPhase),
            ModifierNormalizer.description(of: effectiveModifierFlags),
            ModifierNormalizer.description(of: event.modifierFlags),
            ModifierNormalizer.description(of: sessionModifierFlags),
            suppressionIsEnabled ? "on" : "off",
            decisionDescription
        )
        let hasMovement = abs(normalizedDelta.x) >= 0.01
            || abs(normalizedDelta.y) >= 0.01
        if let deltaGeneration, hasMovement {
            resizeController.submit(
                fingerDelta: normalizedDelta,
                generation: deltaGeneration
            )
        }
        recordScroll(
            summary,
            replaceLast: hasMovement && !isMomentum,
            force: isNewPhysicalSequence || isPhysicalEnd || isMomentumEnd
        )

        return decision.shouldConsume
    }

    private func handleModifierChange(_ flags: NSEvent.ModifierFlags) {
        recordModifiers(flags)

        let configuredModifiers = lock.withLock { self.configuredModifiers }
        guard !ModifierNormalizer.matches(
            flags,
            configured: configuredModifiers
        ) else {
            return
        }
        stopActiveResize(reason: "modifier chord released")
    }

    private func cancelActiveResize(reason: String) {
        if case .cancel(let generation) = captureStateMachine.cancelCapture() {
            resizeController.cancel(
                generation: generation,
                reason: reason
            )
        }
        syncPublishedCaptureState()
    }

    private func handleTimeoutDisable() {
        let now = ProcessInfo.processInfo.systemUptime
        timeoutDisableTimestamps = timeoutDisableTimestamps.filter {
            now - $0 < 10
        }
        timeoutDisableTimestamps.append(now)

        guard timeoutDisableTimestamps.count < 2 else {
            cancelActiveResize(reason: "event tap repeatedly timed out")
            updateHealth(.degraded("Repeated event-tap timeout"))
            return
        }

        stopActiveResize(reason: "event tap timed out", at: now)

        guard let tap = lock.withLock({ eventTap }) else {
            cancelActiveResize(reason: "event tap unavailable after timeout")
            updateHealth(.degraded("Event tap unavailable after timeout"))
            return
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            cancelActiveResize(reason: "event tap could not recover from timeout")
            updateHealth(.degraded("Event tap could not recover from timeout"))
            return
        }

        updateHealth(.running)
        recordScroll(
            "Event tap re-enabled after timeout",
            replaceLast: true,
            force: true
        )
    }

    private func scheduleResizeStop(reason: String) {
        let runLoop = lock.withLock { eventTapRunLoop }
        guard let runLoop else { return }

        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            [weak self] in
            self?.stopActiveResize(reason: reason)
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func stopActiveResize(
        reason: String,
        at now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        if case .cancel(let generation) = captureStateMachine.stopResizing(
            at: now
        ) {
            resizeController.cancel(generation: generation, reason: reason)
            syncPublishedCaptureState()
            publish(force: true)
        }
    }

    private func syncPublishedCaptureState() {
        let description = captureStateMachine.state.description
        lock.withLock {
            publishedCaptureState = description
        }
    }

    private func updateHealth(_ newHealth: Health) {
        lock.withLock {
            health = newHealth
        }
        publish(force: true)
    }

    private func recordScroll(
        _ summary: String,
        replaceLast: Bool,
        force: Bool
    ) {
        if replaceLast {
            lock.withLock {
                lastScrollEvent = summary
            }
        }
        logger.debug("\(summary, privacy: .public)")
        publish(force: force)
    }

    private func recordModifiers(_ flags: NSEvent.ModifierFlags) {
        let summary = "flags=\(ModifierNormalizer.description(of: flags))"
        lock.withLock {
            lastModifierEvent = summary
        }
        logger.debug("\(summary, privacy: .public)")
        publish(force: true)
    }

    private func publish(force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let payload: (Snapshot, SnapshotHandler?)? = lock.withLock {
            guard force || now - lastPublishedAt >= 0.1 else { return nil }
            lastPublishedAt = now
            return (
                Snapshot(
                    health: health,
                    suppressionEnabled: suppressionEnabled,
                    captureState: publishedCaptureState,
                    lastScrollEvent: lastScrollEvent,
                    lastModifierEvent: lastModifierEvent
                ),
                onSnapshotStorage
            )
        }

        guard let payload, let callback = payload.1 else { return }
        Task { @MainActor in
            callback(payload.0)
        }
    }

    private func phaseDescription(_ phase: NSEvent.Phase) -> String {
        if phase.isEmpty { return "none" }

        var values: [String] = []
        if phase.contains(.mayBegin) { values.append("mayBegin") }
        if phase.contains(.began) { values.append("began") }
        if phase.contains(.stationary) { values.append("stationary") }
        if phase.contains(.changed) { values.append("changed") }
        if phase.contains(.ended) { values.append("ended") }
        if phase.contains(.cancelled) { values.append("cancelled") }
        return values.joined(separator: "+")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
