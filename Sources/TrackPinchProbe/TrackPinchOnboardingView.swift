import AppKit
import SwiftUI

struct TrackPinchOnboardingView: View {
    @ObservedObject var model: TrackPinchAppModel

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 13) {
                Label("Set up TrackPinch", systemImage: "sparkles")
                    .font(.headline)

                if model.permissionsReady {
                    gestureStep
                } else {
                    permissionStep
                }
            }
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 11) {
            stepLabel("Step 1 of 2 · Permissions")

            Text(
                "TrackPinch needs permission to recognize the selected gesture and resize the active window."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            SetupPermissionRow(
                title: "Accessibility",
                detail: "Resize the active window",
                isGranted: model.accessibilityTrusted,
                action: model.openAccessibilitySettings
            )
            SetupPermissionRow(
                title: "Input Monitoring",
                detail: "Recognize modifier and scroll events",
                isGranted: model.inputListeningGranted,
                action: model.openInputMonitoringSettings
            )

            Label {
                Text(
                    "Only modifier and scroll metadata used by the gesture is observed. Typed keys are not recorded."
                )
            } icon: {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Check Again") {
                    model.refreshPermissions()
                }
                .controlSize(.small)

                Spacer()

                Button("Grant Missing Permissions") {
                    model.requestPermissions()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var gestureStep: some View {
        VStack(alignment: .leading, spacing: 11) {
            stepLabel("Step 2 of 2 · Try the gesture")

            Text("Hold \(model.modifierGlyphs), then move two fingers on the trackpad.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GestureDirectionGuide()

            Text(
                "TrackPinch resizes the active window from its bottom-right edge. The gesture does not move or snap the window."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Finish Setup") {
                    model.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func stepLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct GestureDirectionGuide: View {
    var body: some View {
        VStack(spacing: 8) {
            directionRow(
                symbol: "arrow.left.and.right",
                title: "Move horizontally",
                result: "Width"
            )
            directionRow(
                symbol: "arrow.up.and.down",
                title: "Move vertically",
                result: "Height"
            )
            directionRow(
                symbol: "arrow.up.left.and.arrow.down.right",
                title: "Move diagonally",
                result: "Both"
            )
        }
    }

    private func directionRow(
        symbol: String,
        title: String,
        result: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
            Spacer()
            Text(result)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SetupPermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(
                systemName: isGranted
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .foregroundStyle(isGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Open Settings", action: action)
                    .controlSize(.small)
            }
        }
    }
}
