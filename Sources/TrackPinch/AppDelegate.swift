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
    private var onboardingWindowController: TrackPinchOnboardingWindowController?
    private var frontmostAppTracker: FrontmostAppTracker!
    private var refreshPermissionsOnTargetChange = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureRuntime()
        configureStatusItem()
        configurePopover()

        let initialPermissionState = refreshPermissions(
            retryUnavailableMonitor: false
        )
        eventTapProbe.setConfiguredModifiers(appModel.modifiers)
        eventTapProbe.setSuppressionEnabled(appModel.isEnabled)
        axLiveResizeController.setSensitivity(appModel.sensitivity)
        if initialPermissionState.accessibilityTrusted {
            ensureEventTapRunning()
        }
        refreshPermissionsOnTargetChange = true

        let shouldPresentOnboarding = !appModel.hasPresentedOnboarding
        if shouldPresentOnboarding
            || CommandLine.arguments.contains("--show-onboarding") {
            DispatchQueue.main.async { [weak self] in
                self?.showOnboardingWindow(
                    markAsPresented: shouldPresentOnboarding
                )
            }
        } else if CommandLine.arguments.contains("--show-popover") {
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.showPopover(relativeTo: button)
            }
        }

        logger.info("TrackPinch launched")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        checkPermissionsAndRetry()
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
        resizePopoverToFitScreen(relativeTo: button)
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
            self?.openAccessibilitySettings()
        }
        appModel.onRefreshPermissions = { [weak self] in
            self?.checkPermissionsAndRetry()
        }
        appModel.onShowOnboarding = { [weak self] in
            self?.showOnboardingWindow()
        }
        appModel.onRetryEventTap = { [weak self] in
            self?.retryEventTapIfPermitted()
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
        popover.contentSize = NSSize(
            width: PopoverSizePolicy.width,
            height: PopoverSizePolicy.idealHeight
        )
    }

    private func showOnboardingWindow(markAsPresented: Bool = false) {
        refreshPermissions()

        if onboardingWindowController == nil {
            onboardingWindowController = TrackPinchOnboardingWindowController(
                model: appModel,
                onFinish: { [weak self] in
                    self?.finishOnboarding()
                }
            )
        }

        if markAsPresented {
            appModel.markOnboardingPresented()
        }

        onboardingWindowController?.present(
            on: statusItem.button?.window?.screen
        )
    }

    private func finishOnboarding() {
        appModel.completeOnboarding()
        guard appModel.hasCompletedOnboarding else { return }

        onboardingWindowController?.close()
        guard let button = statusItem.button else { return }
        showPopover(relativeTo: button)
    }

    private func resizePopoverToFitScreen(
        relativeTo button: NSStatusBarButton
    ) {
        let screen = button.window?.screen ?? NSScreen.main
        let contentHeight = screen.map {
            PopoverSizePolicy.contentHeight(
                forVisibleFrameHeight: $0.visibleFrame.height
            )
        } ?? PopoverSizePolicy.idealHeight

        popover.contentSize = NSSize(
            width: PopoverSizePolicy.width,
            height: contentHeight
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

    @discardableResult
    private func refreshPermissions(
        retryUnavailableMonitor: Bool = true
    ) -> PermissionProbe.State {
        let state = PermissionProbe.state
        appModel.updatePermissions(state)
        eventTapProbe.setAccessibilityTrusted(state.accessibilityTrusted)
        if retryUnavailableMonitor,
           state.accessibilityTrusted {
            ensureEventTapRunning()
        }
        updateStatusItemAppearance()
        return state
    }

    private func checkPermissionsAndRetry() {
        let state = refreshPermissions(retryUnavailableMonitor: false)
        if state.accessibilityTrusted {
            appModel.updatePermissionAction("Accessibility granted")
            ensureEventTapRunning()
        }
    }

    private func requestPermissionsAndRetry() {
        let state = refreshPermissions(retryUnavailableMonitor: false)
        if state.accessibilityTrusted {
            appModel.updatePermissionAction("Accessibility already granted")
            ensureEventTapRunning()
            return
        }

        _ = PermissionProbe.requestAccessibility()
        appModel.updatePermissionAction("Requested Accessibility access")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.checkPermissionsAndRetry()
        }
    }

    private func ensureEventTapRunning() {
        switch eventTapProbe.snapshot().health {
        case .stopped:
            eventTapProbe.start()
        case .unavailable:
            eventTapProbe.retry()
        case .starting, .running, .degraded:
            break
        }
    }

    private func retryEventTapIfPermitted() {
        let state = refreshPermissions(retryUnavailableMonitor: false)
        guard state.accessibilityTrusted else {
            appModel.updatePermissionAction("Accessibility required")
            return
        }
        eventTapProbe.retry()
    }

    private func openAccessibilitySettings() {
        let opened = PermissionProbe.openAccessibilitySettings()
        appModel.updatePermissionAction(
            opened
                ? "Opened Accessibility Settings"
                : "Could not open Accessibility Settings"
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
