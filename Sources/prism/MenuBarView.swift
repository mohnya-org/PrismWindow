import SwiftUI

struct MenuBarView: View {
    private enum MoveViewStyle: String, CaseIterable {
        case buttons
        case layout

        var title: String {
            switch self {
            case .buttons:
                return "Buttons"
            case .layout:
                return "Layout"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarMoveViewStyle") private var moveViewStyleRawValue = MoveViewStyle.buttons.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !appState.currentLayoutRules.isEmpty {
                Toggle(isOn: $appState.autoApplyRules) {
                    Label("Auto-apply rules", systemImage: "bolt.fill")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            if !appState.isAccessibilityTrusted {
                permissionsCard
            }

            moveSection

            HStack {
                Button("Settings…") {
                    openSettings()
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prism")
                .font(.title2.bold())
            Text("Move windows between displays")
                .font(.callout)
                .foregroundStyle(.secondary)
            if appState.lastMessage != "Ready" {
                Text(appState.lastMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility required", systemImage: "exclamationmark.triangle")
                .font(.headline)

            Button("Grant Access") {
                appState.refreshPermissions(prompt: true)
            }
        }
    }

    private var moveSection: some View {
        let displays = DisplayInfo.availableDisplays()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                moveContextHeader

                Spacer()

                Picker("Move view", selection: moveViewStyleBinding) {
                    ForEach(MoveViewStyle.allCases, id: \.rawValue) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if displays.isEmpty {
                Text("No displays detected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if moveViewStyle == .buttons {
                buttonSelector(displays: displays)
            } else {
                layoutSelector(displays: displays)
            }
        }
    }

    private func buttonSelector(displays: [DisplayInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                Button {
                    moveFocusedWindow(to: display.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Move to \(display.name)")
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }

                        Text("Target: Display \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(appState.isHandlingMove)
            }
        }
    }

    private func layoutSelector(displays: [DisplayInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DisplayLayoutSelectorView(
                displays: displays,
                isHandlingMove: appState.isHandlingMove,
                onSelect: moveFocusedWindow(to:)
            )
            .frame(height: 220)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Displays are shown in the current arrangement. Click a screen to move the focused window there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var moveViewStyle: MoveViewStyle {
        MoveViewStyle(rawValue: moveViewStyleRawValue) ?? .buttons
    }

    private var moveViewStyleBinding: Binding<MoveViewStyle> {
        Binding(
            get: { moveViewStyle },
            set: { moveViewStyleRawValue = $0.rawValue }
        )
    }

    private var moveContextHeader: some View {
        HStack(spacing: 10) {
            if let appIcon = appState.currentAppDescriptor?.icon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Image(systemName: "app.dashed")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Moving App")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentAppName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var currentAppName: String {
        appState.currentAppDescriptor?.displayName ?? "Focused app"
    }

    private func moveFocusedWindow(to displayID: CGDirectDisplayID) {
        Task {
            await appState.moveFocusedWindow(to: displayID)
        }
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct DisplayLayout {
    private let bounds: CGRect
    private let scale: CGFloat
    private let xInset: CGFloat
    private let yInset: CGFloat

    init(displays: [DisplayInfo], canvasSize: CGSize, padding: CGFloat = 12) {
        let combinedBounds = displays.dropFirst().reduce(displays[0].frame) { partial, display in
            partial.union(display.frame)
        }
        let usableWidth = max(canvasSize.width - (padding * 2), 1)
        let usableHeight = max(canvasSize.height - (padding * 2), 1)
        let scale = min(usableWidth / combinedBounds.width, usableHeight / combinedBounds.height)
        let contentWidth = combinedBounds.width * scale
        let contentHeight = combinedBounds.height * scale

        bounds = combinedBounds
        self.scale = scale
        xInset = (canvasSize.width - contentWidth) / 2
        yInset = (canvasSize.height - contentHeight) / 2
    }

    func frame(for display: DisplayInfo) -> CGRect {
        CGRect(
            x: xInset + ((display.frame.minX - bounds.minX) * scale),
            y: yInset + ((display.frame.minY - bounds.minY) * scale),
            width: display.frame.width * scale,
            height: display.frame.height * scale
        )
    }
}

private struct DisplayLayoutSelectorView: View {
    let displays: [DisplayInfo]
    let isHandlingMove: Bool
    let onSelect: (CGDirectDisplayID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = DisplayLayout(displays: displays, canvasSize: proxy.size)

            ZStack(alignment: .topLeading) {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    let frame = layout.frame(for: display)

                    DisplayLayoutTile(
                        index: index,
                        display: display,
                        frame: frame,
                        isHandlingMove: isHandlingMove,
                        onSelect: onSelect
                    )
                }
            }
        }
        .clipped()
        .contentShape(Rectangle())
    }
}

private struct DisplayLayoutTile: View {
    let index: Int
    let display: DisplayInfo
    let frame: CGRect
    let isHandlingMove: Bool
    let onSelect: (CGDirectDisplayID) -> Void

    private var isCompact: Bool {
        frame.width < 120 || frame.height < 90
    }

    var body: some View {
        Button {
            onSelect(display.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if !isCompact {
                    Text("Move to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(display.name)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(isCompact ? 1 : 2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                if !isCompact {
                    Text("Target display: \(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(isCompact ? 8 : 10)
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .clipped()
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHandlingMove ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.14))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.secondary.opacity(0.35), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isHandlingMove)
        .position(x: frame.midX, y: frame.midY)
    }
}
