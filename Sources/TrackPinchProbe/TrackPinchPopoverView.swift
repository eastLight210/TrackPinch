import AppKit
import SwiftUI
import TrackPinchCore

struct TrackPinchPopoverView: View {
    @ObservedObject var model: TrackPinchAppModel
    @State private var diagnosticsExpanded = false

    private let modifierOptions: [ModifierOption] = [
        ModifierOption(name: "Function", glyph: "fn", flag: .function),
        ModifierOption(name: "Control", glyph: "⌃", flag: .control),
        ModifierOption(name: "Option", glyph: "⌥", flag: .option),
        ModifierOption(name: "Command", glyph: "⌘", flag: .command),
        ModifierOption(name: "Shift", glyph: "⇧", flag: .shift),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    gestureCard
                    permissionCard
                    diagnostics
                }
                .padding(14)
            }

            Divider()
            footer
        }
        .frame(width: 370, height: 560)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("TrackPinch")
                    .font(.headline)
                StatusLabel(
                    title: model.statusTitle,
                    state: model.operationalState
                )
            }

            Spacer()

            Toggle(
                "Enable TrackPinch",
                isOn: Binding(
                    get: { model.isEnabled },
                    set: model.setEnabled
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel("Enable TrackPinch")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var gestureCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Resize gesture", systemImage: "hand.draw")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(model.modifierGlyphs)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("Hold the selected keys and move two fingers to resize the active window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    ForEach(modifierOptions) { option in
                        ModifierKeyButton(
                            option: option,
                            isSelected: model.modifiers.contains(option.flag)
                        ) {
                            model.toggleModifier(option.flag)
                        }
                    }
                }

                Divider()

                HStack {
                    Label("Sensitivity", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(model.sensitivity, format: .number.precision(.fractionLength(1)))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    Text("×")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { model.sensitivity },
                        set: model.setSensitivity
                    ),
                    in: TrackPinchSettings.sensitivityRange,
                    step: 0.1
                ) {
                    Text("Resize sensitivity")
                } minimumValueLabel: {
                    Text("Fine")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Fast")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Applies to both width and height")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Reset") {
                        model.resetSensitivity()
                    }
                    .buttonStyle(.link)
                    .disabled(model.sensitivity == TrackPinchSettings.defaultSensitivity)
                }
            }
        }
    }

    private var permissionCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Permissions", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))

                PermissionRow(
                    title: "Accessibility",
                    isGranted: model.accessibilityTrusted,
                    action: model.openAccessibilitySettings
                )
                PermissionRow(
                    title: "Input Monitoring",
                    isGranted: model.inputListeningGranted,
                    action: model.openInputMonitoringSettings
                )

                if !model.accessibilityTrusted || !model.inputListeningGranted {
                    Button("Grant Missing Permissions") {
                        model.requestPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var diagnostics: some View {
        SettingsCard {
            DisclosureGroup(isExpanded: $diagnosticsExpanded) {
                VStack(alignment: .leading, spacing: 9) {
                    DiagnosticRow(title: "Target", value: model.targetAppName)
                    DiagnosticRow(
                        title: "Input monitor",
                        value: model.eventTapHealth.description
                    )
                    DiagnosticRow(title: "Capture", value: model.captureState)
                    DiagnosticRow(title: "Live resize", value: model.liveResizeResult)
                    DiagnosticRow(title: "Resize test", value: model.lastAXResult)
                    DiagnosticRow(
                        title: "Last modifiers",
                        value: model.lastModifierEvent
                    )
                    DiagnosticRow(title: "Last input", value: model.lastScrollEvent)
                    DiagnosticRow(
                        title: "Permission action",
                        value: model.lastPermissionAction
                    )

                    HStack {
                        Button("Retry Monitor") {
                            model.retryEventTap()
                        }
                        Button("Test Resize") {
                            model.runAXProbe()
                        }
                        .disabled(!model.accessibilityTrusted || model.targetAppName == "None")
                        Spacer()
                        Button("Check Again") {
                            model.refreshPermissions()
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.top, 9)
            } label: {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.versionDescription)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit TrackPinch") {
                model.quit()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

private struct ModifierOption: Identifiable {
    let name: String
    let glyph: String
    let flag: NSEvent.ModifierFlags

    var id: UInt { flag.rawValue }
}

private struct ModifierKeyButton: View {
    let option: ModifierOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(option.glyph)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(
            isSelected
                ? Color.accentColor
                : Color.primary.opacity(0.055)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.09))
        }
        .help(option.name)
        .accessibilityLabel("\(option.name) modifier")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct StatusLabel: View {
    let title: String
    let state: TrackPinchAppModel.OperationalState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch state {
        case .active:
            return .green
        case .paused:
            return .secondary
        case .attention:
            return .orange
        case .starting:
            return .blue
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
            Text(title)
                .font(.callout)
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

private struct DiagnosticRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            }
    }
}
