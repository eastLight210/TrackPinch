import AppKit

@MainActor
final class FrontmostAppTracker {
    private let ownBundleIdentifier: String
    private var activationObserver: NSObjectProtocol?

    private(set) var lastExternalPID: pid_t?
    private(set) var lastExternalAppName = "None"
    var onTargetChange: ((pid_t?, String) -> Void)? {
        didSet {
            onTargetChange?(lastExternalPID, lastExternalAppName)
        }
    }

    init(ownBundleIdentifier: String) {
        self.ownBundleIdentifier = ownBundleIdentifier

        update(with: NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let application = notification.userInfo?[
                    NSWorkspace.applicationUserInfoKey
                ] as? NSRunningApplication
            else {
                return
            }

            MainActor.assumeIsolated {
                self?.update(with: application)
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                activationObserver
            )
        }
    }

    private func update(with application: NSRunningApplication?) {
        guard
            let application,
            application.bundleIdentifier != ownBundleIdentifier
        else {
            return
        }

        lastExternalPID = application.processIdentifier
        lastExternalAppName = application.localizedName ?? "PID \(application.processIdentifier)"
        onTargetChange?(lastExternalPID, lastExternalAppName)
    }
}
