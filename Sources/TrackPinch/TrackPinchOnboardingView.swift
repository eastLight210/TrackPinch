import SwiftUI

struct TrackPinchOnboardingView: View {
    @ObservedObject var model: TrackPinchAppModel
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)

            Divider()

            setupContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, idealWidth: 700, minHeight: 540, idealHeight: 540)
        .background(.regularMaterial)
        .animation(.easeInOut(duration: 0.2), value: model.permissionsReady)
    }

    private var sidebar: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.24),
                    Color.accentColor.opacity(0.08),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                TrackPinchAppMark()

                Text("TrackPinch")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .padding(.top, 17)

                Text("Resize the active window with one fluid gesture.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 17) {
                    OnboardingStepRow(
                        number: 1,
                        title: "Allow Accessibility",
                        state: stepState(for: 1)
                    )
                    OnboardingStepRow(
                        number: 2,
                        title: "Learn the gesture",
                        state: stepState(for: 2)
                    )
                }
                .padding(.top, 34)

                Spacer()

                MenuBarHomeCard()
            }
            .padding(.horizontal, 25)
            .padding(.top, 56)
            .padding(.bottom, 25)
        }
    }

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.permissionsReady ? "STEP 2 OF 2" : "STEP 1 OF 2")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text(model.permissionsReady ? "Try the resize gesture" : "Allow window control")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .padding(.top, 8)

            Text(
                model.permissionsReady
                    ? "You are ready. Use the selected modifier and two-finger movement on any resizable window."
                    : "TrackPinch uses macOS Accessibility to resize the window you are working in."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

            Group {
                if model.permissionsReady {
                    gestureStep
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    permissionStep
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.top, 27)

            Spacer(minLength: 20)

            Divider()

            actionBar
                .padding(.top, 17)
        }
        .padding(.horizontal, 34)
        .padding(.top, 55)
        .padding(.bottom, 25)
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            SetupPermissionRow(
                title: "Accessibility",
                detail: "Read and update the active window size",
                isGranted: model.accessibilityTrusted,
                action: model.openAccessibilitySettings
            )

            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your input stays private")
                        .font(.callout.weight(.semibold))
                    Text("TrackPinch observes only modifier and scroll metadata needed for the gesture. Typed keys are not recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(13)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.16))
            }

            Text("Choose Set Up Accessibility, then enable TrackPinch in the macOS privacy list. Return here and TrackPinch will check again automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gestureStep: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 13) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Hold these keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.modifierGlyphs)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                }

                Spacer()

                Text("then move two fingers")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(13)
            .background(Color.primary.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            }

            HStack(spacing: 9) {
                GestureDirectionCard(
                    symbol: "arrow.left.and.right",
                    title: "Horizontal",
                    result: "Width"
                )
                GestureDirectionCard(
                    symbol: "arrow.up.and.down",
                    title: "Vertical",
                    result: "Height"
                )
                GestureDirectionCard(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    title: "Diagonal",
                    result: "Both"
                )
            }

            Label {
                Text("The active window resizes from its bottom-right edge. TrackPinch does not move or snap the window.")
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if model.permissionsReady {
                Text("Reopen this guide anytime from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(model.hasCompletedOnboarding ? "Done" : "Finish Setup") {
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else {
                Spacer()

                Button("Check Again") {
                    model.refreshPermissions()
                }

                Button("Set Up Accessibility") {
                    model.requestPermissions()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    private func stepState(for step: Int) -> OnboardingStepState {
        switch step {
        case 1:
            return model.permissionsReady ? .complete : .current
        case 2:
            guard model.permissionsReady else { return .pending }
            if model.hasCompletedOnboarding { return .complete }
            return .current
        default:
            return .pending
        }
    }
}

private struct TrackPinchAppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.accentColor.gradient)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 64, height: 64)
        .shadow(color: Color.accentColor.opacity(0.24), radius: 16, y: 8)
        .accessibilityHidden(true)
    }
}

private struct MenuBarHomeCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text("Lives in your menu bar")
                    .font(.caption.weight(.semibold))
                Text("No Dock icon after setup.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        }
    }
}

private enum OnboardingStepState {
    case pending
    case current
    case complete
}

private struct OnboardingStepRow: View {
    let number: Int
    let title: String
    let state: OnboardingStepState

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(circleFill)
                Circle()
                    .strokeBorder(circleStroke, lineWidth: 1)

                if state == .complete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(numberColor)
                }
            }
            .frame(width: 25, height: 25)

            Text(title)
                .font(.callout.weight(state == .current ? .semibold : .regular))
                .foregroundStyle(state == .pending ? .secondary : .primary)
        }
    }

    private var circleFill: Color {
        switch state {
        case .complete, .current:
            return .accentColor
        case .pending:
            return Color.primary.opacity(0.04)
        }
    }

    private var circleStroke: Color {
        state == .pending ? Color.primary.opacity(0.13) : .clear
    }

    private var numberColor: Color {
        state == .current ? .white : .secondary
    }
}

private struct GestureDirectionCard: View {
    let symbol: String
    let title: String
    let result: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(height: 23)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(result)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) movement changes \(result.lowercased())")
    }
}

private struct SetupPermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(
                systemName: isGranted
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Granted")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Button("Open Settings…", action: action)
                    .controlSize(.small)
            }
        }
        .padding(13)
        .background(Color.primary.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        }
    }
}
