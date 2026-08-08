import AppKit
import SwiftUI

@MainActor
final class TrackPinchOnboardingWindowController: NSWindowController {
    private static let contentSize = NSSize(width: 700, height: 540)

    private var hasPlacedWindow = false

    init(
        model: TrackPinchAppModel,
        onFinish: @escaping () -> Void
    ) {
        let rootView = TrackPinchOnboardingView(
            model: model,
            onFinish: onFinish
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Welcome to TrackPinch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        window.contentViewController = hostingController
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(on screen: NSScreen?) {
        guard let window else { return }

        let isOnConnectedDisplay = NSScreen.screens.contains {
            $0.visibleFrame.intersects(window.frame)
        }
        if !hasPlacedWindow || !isOnConnectedDisplay {
            placeWindow(window, on: screen ?? NSScreen.main)
            hasPlacedWindow = true
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func placeWindow(_ window: NSWindow, on screen: NSScreen?) {
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let windowFrame = window.frame
        let origin = NSPoint(
            x: visibleFrame.midX - windowFrame.width / 2,
            y: visibleFrame.midY - windowFrame.height / 2
        )
        window.setFrameOrigin(origin)
    }
}
