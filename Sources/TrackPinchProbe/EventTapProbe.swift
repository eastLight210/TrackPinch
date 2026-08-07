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

final class EventTapProbe {
    enum Health: Equatable {
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

    struct Snapshot {
        let health: Health
        let suppressionEnabled: Bool
        let captureState: String
        let lastScrollEvent: String
        let lastModifierEvent: String
    }

    private enum CaptureState {
        case idle
        case physical(generation: UInt64)
        case swallowing(generation: UInt64)
        case draining(generation: UInt64, deadline: TimeInterval)

        var description: String {
            switch self {
            case .idle: return "Idle"
            case .physical: return "Resizing"
            case .swallowing: return "Swallowing"
            case .draining: return "Draining"
            }
        }

        var generation: UInt64? {
            switch self {
            case .idle:
                return nil
            case .physical(let generation),
                 .swallowing(let generation),
                 .draining(let generation, _):
                return generation
            }
        }
    }

    private let logger = Logger(
        subsystem: "dev.badgerworks.trackpinch",
        category: "event-tap-probe"
    )
    private let resizeController: AXLiveResizeController
    private let lock = NSLock()

    private var eventTap: CFMachPort?
    private var eventTapRunLoop: CFRunLoop?
    private var eventTapThread: Thread?
    private var health: Health = .stopped
    private var suppressionEnabled = false
    private var configuredModifiers = ModifierNormalizer.defaultGestureModifiers
    private var lastScrollEvent = "No scroll observed"
    private var lastModifierEvent = "No modifier observed"
    private var onSnapshotStorage: ((Snapshot) -> Void)?
    private var lastPublishedAt: TimeInterval = 0
    private var targetPID: pid_t?

    // Accessed only on the dedicated event-tap thread.
    private var captureState: CaptureState = .idle
    private var timeoutDisableTimestamps: [TimeInterval] = []
    private var nextGeneration: UInt64 = 0

    init(resizeController: AXLiveResizeController) {
        self.resizeController = resizeController
    }

    var onSnapshot: ((Snapshot) -> Void)? {
        get {
            lock.withLock { onSnapshotStorage }
        }
        set {
            lock.withLock { onSnapshotStorage = newValue }
        }
    }

    func start() {
        let thread: Thread? = lock.withLock {
            guard eventTapThread == nil else { return nil }

            health = .starting
            let thread = Thread { [weak self] in
                self?.installAndRun()
            }
            thread.name = "TrackPinch Event Tap"
            thread.qualityOfService = .userInteractive
            eventTapThread = thread
            return thread
        }

        publish(force: true)
        thread?.start()
    }

    func retry() {
        stop()
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 0.25
        ) { [weak self] in
            self?.start()
        }
    }

    func stop() {
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
        logger.info("Suppression enabled=\(enabled, privacy: .public)")
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
                captureState: captureState.description,
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
                eventTapThread = nil
            }
            publish(force: true)
            return
        }

        let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        )
        let runLoop = CFRunLoopGetCurrent()

        lock.withLock {
            eventTap = tap
            eventTapRunLoop = runLoop
            health = .running
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        publish(force: true)
        logger.info("Active session event tap installed")
        CFRunLoopRun()

        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(tap)
        cancelActiveResize(reason: "event tap stopped")

        lock.withLock {
            eventTap = nil
            eventTapRunLoop = nil
            eventTapThread = nil
            if case .degraded = health {
                // Preserve the diagnostic until an explicit retry.
            } else {
                health = .stopped
            }
        }
        publish(force: true)
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
            (suppressionEnabled, targetPID, configuredModifiers)
        }
        let isConfiguredModifier = ModifierNormalizer.matches(
            effectiveModifierFlags,
            configured: configuration.2
        )
        let suppressionIsEnabled = configuration.0
        let candidatePID = configuration.1

        if case .draining(_, let deadline) = captureState, now > deadline {
            captureState = .idle
        }

        let shouldConsume: Bool
        var deltaGeneration: UInt64?
        switch captureState {
        case .idle:
            if suppressionIsEnabled,
               isConfiguredModifier,
               event.hasPreciseScrollingDeltas,
               !isMomentum,
               isNewPhysicalSequence,
               let candidatePID {
                let generation = beginCapture(pid: candidatePID)
                deltaGeneration = generation
                shouldConsume = true
            } else {
                shouldConsume = false
            }

        case .physical(let generation):
            shouldConsume = true
            if isPhysicalEnd {
                resizeController.finish(generation: generation)
                captureState = .draining(
                    generation: generation,
                    deadline: now + 0.3
                )
            } else if !isMomentum, !phase.isEmpty {
                deltaGeneration = generation
            }

        case .swallowing(let generation):
            shouldConsume = true
            if isPhysicalEnd {
                captureState = .draining(
                    generation: generation,
                    deadline: now + 0.3
                )
            }

        case .draining(let generation, _):
            if isMomentum {
                shouldConsume = true
                if isMomentumEnd {
                    captureState = .idle
                } else {
                    captureState = .draining(
                        generation: generation,
                        deadline: now + 5
                    )
                }
            } else if isNewPhysicalSequence {
                if suppressionIsEnabled,
                   isConfiguredModifier,
                   event.hasPreciseScrollingDeltas,
                   let candidatePID {
                    let newGeneration = beginCapture(pid: candidatePID)
                    deltaGeneration = newGeneration
                    shouldConsume = true
                } else {
                    captureState = .idle
                    shouldConsume = false
                }
            } else {
                shouldConsume = true
            }
        }

        let normalizedDelta = ScrollDeltaNormalizer.deviceIndependent(
            x: event.scrollingDeltaX,
            y: event.scrollingDeltaY,
            isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice
        )
        let decision = shouldConsume ? "consume" : "pass"
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
            decision
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

        return shouldConsume
    }

    private func beginCapture(pid: pid_t) -> UInt64 {
        nextGeneration &+= 1
        let generation = nextGeneration
        captureState = .physical(generation: generation)
        resizeController.begin(generation: generation, pid: pid)
        return generation
    }

    private func handleModifierChange(_ flags: NSEvent.ModifierFlags) {
        recordModifiers(flags)

        guard case .physical(let generation) = captureState else { return }
        let configuredModifiers = lock.withLock { self.configuredModifiers }
        guard !ModifierNormalizer.matches(
            flags,
            configured: configuredModifiers
        ) else {
            return
        }

        captureState = .swallowing(generation: generation)
        resizeController.cancel(
            generation: generation,
            reason: "modifier chord released"
        )
        publish(force: true)
    }

    private func cancelActiveResize(reason: String) {
        if let generation = captureState.generation {
            resizeController.cancel(
                generation: generation,
                reason: reason
            )
        }
        captureState = .idle
    }

    private func handleTimeoutDisable() {
        let now = ProcessInfo.processInfo.systemUptime
        timeoutDisableTimestamps = timeoutDisableTimestamps.filter {
            now - $0 < 10
        }
        timeoutDisableTimestamps.append(now)
        cancelActiveResize(reason: "event tap timed out")

        guard timeoutDisableTimestamps.count < 2 else {
            updateHealth(.degraded("Repeated event-tap timeout"))
            return
        }

        let tap = lock.withLock { eventTap }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            updateHealth(.running)
            recordScroll(
                "Event tap re-enabled after timeout",
                replaceLast: true,
                force: true
            )
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
        let payload: (Snapshot, ((Snapshot) -> Void)?)? = lock.withLock {
            guard force || now - lastPublishedAt >= 0.1 else { return nil }
            lastPublishedAt = now
            return (
                Snapshot(
                    health: health,
                    suppressionEnabled: suppressionEnabled,
                    captureState: captureState.description,
                    lastScrollEvent: lastScrollEvent,
                    lastModifierEvent: lastModifierEvent
                ),
                onSnapshotStorage
            )
        }

        guard let payload, let callback = payload.1 else { return }
        DispatchQueue.main.async {
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
