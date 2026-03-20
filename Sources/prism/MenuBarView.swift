import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            displayLayout

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

    private var displayLayout: some View {
        let displays = DisplayInfo.availableDisplays()

        return Group {
            if displays.isEmpty {
                Text("No displays detected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                MenuBarDisplayLayoutView(
                    displays: displays,
                    focusedAppDescriptor: appState.currentAppDescriptor,
                    isHandlingMove: appState.isHandlingMove,
                    onSelect: moveFocusedWindow(to:)
                )
                .frame(height: 200)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
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

// MARK: - Display Layout

private struct MenuBarDisplayLayout {
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

private struct MenuBarDisplayLayoutView: View {
    let displays: [DisplayInfo]
    let focusedAppDescriptor: AppDescriptor?
    let isHandlingMove: Bool
    let onSelect: (CGDirectDisplayID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = MenuBarDisplayLayout(displays: displays, canvasSize: proxy.size)

            ZStack(alignment: .topLeading) {
                ForEach(displays, id: \.id) { display in
                    let frame = layout.frame(for: display)
                    let isFocusedHere = isAppOnDisplay(display)

                    Button {
                        onSelect(display.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(display.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            if isFocusedHere, let app = focusedAppDescriptor {
                                HStack(spacing: 5) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .interpolation(.high)
                                            .frame(width: 22, height: 22)
                                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    }
                                    Text(app.displayName)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(0.18))
                                )
                            }
                        }
                        .padding(8)
                        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isFocusedHere ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.12))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isFocusedHere ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: isFocusedHere ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isHandlingMove)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .clipped()
        .contentShape(Rectangle())
    }

    private func isAppOnDisplay(_ display: DisplayInfo) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windowObj = appElement.optionalValue(for: kAXFocusedWindowAttribute as CFString),
              CFGetTypeID(windowObj) == AXUIElementGetTypeID() else {
            return false
        }
        let window = unsafeDowncast(windowObj, to: AXUIElement.self)
        guard let position = cgPoint(from: window.optionalValue(for: kAXPositionAttribute as CFString)),
              let size = cgSize(from: window.optionalValue(for: kAXSizeAttribute as CFString)) else {
            return false
        }
        let frame = CGRect(origin: position, size: size)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return display.frame.contains(center)
    }
}
