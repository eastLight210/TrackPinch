import AppKit
import OSLog
import SwiftUI
import TrackPinchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let logger = Logger(
        subsystem: "dev.badgerworks.trackpinch",
        category: "application"
    )
    private let settingsStore = TrackPinchSettingsStore()
    private let axLiveResizeController = AXLiveResizeController()
    private let axResizeProbe = AXResizeProbe()

    private lazy var appModel = TrackPinchAppModel(
        settingsStore: settingsStore
    )
    private lazy var eventTapProbe = EventTapProbe(
        resizeController: axLiveResizeController
    )

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var frontmostAppTracker: FrontmostAppTracker!
    private var refreshPermissionsOnTargetChange = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureRuntime()
        configureStatusItem()
        configurePopover()

        refreshPermissions(retryUnavailableMonitor: false)
        eventTapProbe.setConfiguredModifiers(appModel.modifiers)
        eventTapProbe.setSuppressionEnabled(appModel.isEnabled)
        axLiveResizeController.setSensitivity(appModel.sensitivity)
        eventTapProbe.start()
        refreshPermissionsOnTargetChange = true

        let shouldPresentOnboarding = !appModel.hasPresentedOnboarding
        if shouldPresentOnboarding
            || CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.statusItem.button else {
                    return
                }
                self.showPopover(relativeTo: button)
                if shouldPresentOnboarding {
                    self.appModel.markOnboardingPresented()
                }
            }
        }

        logger.info("TrackPinch launched")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapProbe.stop()
        frontmostAppTracker.stop()
    }

    func popoverWillShow(_ notification: Notification) {
        refreshPermissions()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        showPopover(relativeTo: sender)
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureRuntime() {
        let bundleIdentifier = Bundle.main.bundleIdentifier
            ?? "dev.badgerworks.trackpinch"
        frontmostAppTracker = FrontmostAppTracker(
            ownBundleIdentifier: bundleIdentifier
        )
        frontmostAppTracker.onTargetChange = { [weak self] pid, appName in
            self?.eventTapProbe.setTargetPID(pid)
            self?.appModel.updateTarget(appName: appName)
            if self?.refreshPermissionsOnTargetChange == true {
                self?.refreshPermissions()
            }
        }

        eventTapProbe.onSnapshot = { [weak self] snapshot in
            self?.appModel.updateEventTap(snapshot)
            self?.updateStatusItemAppearance()
        }
        axLiveResizeController.onStatus = { [weak self] status in
            self?.appModel.updateLiveResize(status: status)
        }

        appModel.onEnabledChanged = { [weak self] enabled in
            self?.eventTapProbe.setSuppressionEnabled(enabled)
            self?.updateStatusItemAppearance()
        }
        appModel.onSensitivityChanged = { [weak self] sensitivity in
            self?.axLiveResizeController.setSensitivity(sensitivity)
        }
        appModel.onModifiersChanged = { [weak self] modifiers in
            self?.eventTapProbe.setConfiguredModifiers(modifiers)
        }
        appModel.onRequestPermissions = { [weak self] in
            self?.requestPermissionsAndRetry()
        }
        appModel.onOpenAccessibilitySettings = { [weak self] in
            self?.openSettings(.accessibility)
        }
        appModel.onOpenInputMonitoringSettings = { [weak self] in
            self?.openSettings(.inputMonitoring)
        }
        appModel.onRefreshPermissions = { [weak self] in
            self?.checkPermissionsAndRetry()
        }
        appModel.onRetryEventTap = { [weak self] in
            self?.eventTapProbe.retry()
        }
        appModel.onRunAXProbe = { [weak self] in
            self?.runAXResizeProbe()
        }
        appModel.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("TrackPinch")
        updateStatusItemAppearance()
    }

    private func configurePopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: TrackPinchPopoverView(model: appModel)
        )
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        switch appModel.operationalState {
        case .active:
            symbolName = "arrow.up.left.and.arrow.down.right"
            button.contentTintColor = nil
        case .paused:
            symbolName = "pause.circle"
            button.contentTintColor = .secondaryLabelColor
        case .attention:
            symbolName = "exclamationmark.triangle"
            button.contentTintColor = .systemOrange
        case .starting:
            symbolName = "arrow.triangle.2.circlepath"
            button.contentTintColor = .secondaryLabelColor
        }

        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "TrackPinch"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "TrackPinch — \(appModel.statusTitle)"
        button.setAccessibilityValue(appModel.statusTitle)
    }

    private func refreshPermissions(
        retryUnavailableMonitor: Bool = true
    ) {
        let state = PermissionProbe.state
        appModel.updatePermissions(state)
        eventTapProbe.setPermissionState(
            accessibilityTrusted: state.accessibilityTrusted,
            inputListeningGranted: state.inputListeningGranted
        )
        if retryUnavailableMonitor,
           state.accessibilityTrusted,
           state.inputListeningGranted {
            switch eventTapProbe.snapshot().health {
            case .stopped, .unavailable:
                eventTapProbe.retry()
            case .starting, .running, .degraded:
                break
            }
        }
        updateStatusItemAppearance()
    }

    private func checkPermissionsAndRetry() {
        refreshPermissions(retryUnavailableMonitor: false)
        if appModel.accessibilityTrusted,
           appModel.inputListeningGranted {
            appModel.updatePermissionAction("Permissions granted")
            eventTapProbe.retry()
        }
    }

    private func requestPermissionsAndRetry() {
        let requestedState = PermissionProbe.request()
        appModel.updatePermissions(requestedState)
        eventTapProbe.setPermissionState(
            accessibilityTrusted: requestedState.accessibilityTrusted,
            inputListeningGranted: requestedState.inputListeningGranted
        )
        let missingPane = PermissionProbe.nextMissingPane(for: requestedState)
        let openedSettings = missingPane.map(PermissionProbe.openSettings) ?? false

        if let missingPane {
            let paneName = missingPane == .accessibility
                ? "Accessibility"
                : "Input Monitoring"
            appModel.updatePermissionAction(
                openedSettings
                    ? "Opened \(paneName) Settings"
                    : "Could not open \(paneName) Settings"
            )
        } else {
            appModel.updatePermissionAction("Permissions already granted")
        }

        eventTapProbe.retry()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshPermissions()
        }
    }

    private func openSettings(_ pane: PermissionProbe.SettingsPane) {
        let opened = PermissionProbe.openSettings(pane)
        let paneName = pane == .accessibility
            ? "Accessibility"
            : "Input Monitoring"
        appModel.updatePermissionAction(
            opened
                ? "Opened \(paneName) Settings"
                : "Could not open \(paneName) Settings"
        )
    }

    private func runAXResizeProbe() {
        guard let pid = frontmostAppTracker.lastExternalPID else {
            appModel.updateAXResult("No external frontmost app recorded")
            return
        }

        let appName = frontmostAppTracker.lastExternalAppName
        appModel.updateAXResult("Running against \(appName)…")
        axResizeProbe.run(pid: pid) { [weak self] result in
            self?.appModel.updateAXResult("\(appName): \(result.message)")
        }
    }
}
