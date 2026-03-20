import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Prism")
                    .font(.title2.bold())
                if appState.lastMessage != "Ready" {
                    Text(appState.lastMessage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            // Auto-apply toggle
            if !appState.currentLayoutRules.isEmpty {
                Toggle(isOn: $appState.autoApplyRules) {
                    Label("Auto-apply rules on focus", systemImage: "bolt.fill")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            // Permissions or display layout
            if !appState.isAccessibilityTrusted {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Button("Grant Access") {
                        appState.refreshPermissions(prompt: true)
                    }
                    .controlSize(.small)
                }
            } else {
                displayLayout
            }

            // Footer
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
        .frame(width: 400)
    }

    private var displayLayout: some View {
        let displays = DisplayInfo.availableDisplays()

        return VStack(alignment: .leading, spacing: 6) {
            Text("Click a display to move the focused window")
                .font(.caption)
                .foregroundStyle(.secondary)

            if displays.isEmpty {
                Text("No displays detected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                MenuBarDisplayLayoutView(
                    displays: displays,
                    focusedAppDescriptor: appState.currentAppDescriptor,
                    isHandlingMove: appState.isHandlingMove,
                    onSelect: moveFocusedWindow(to:)
                )
                .frame(height: 200)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    init(displays: [DisplayInfo], canvasSize: CGSize, padding: CGFloat = 8) {
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

    @State private var hoveredDisplayID: CGDirectDisplayID?

    var body: some View {
        GeometryReader { proxy in
            let layout = MenuBarDisplayLayout(displays: displays, canvasSize: proxy.size)

            ZStack(alignment: .topLeading) {
                ForEach(displays, id: \.id) { display in
                    let frame = layout.frame(for: display)
                    let isFocusedHere = isAppOnDisplay(display)
                    let isHovered = hoveredDisplayID == display.id

                    Button {
                        onSelect(display.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(display.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            if isFocusedHere, let app = focusedAppDescriptor {
                                HStack(spacing: 6) {
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
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.15))
                                )
                            } else if !isFocusedHere {
                                Text("Click to move here")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .opacity(isHovered ? 1 : 0)
                            }
                        }
                        .padding(8)
                        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isFocusedHere
                                    ? Color.accentColor.opacity(0.1)
                                    : isHovered
                                        ? Color.secondary.opacity(0.18)
                                        : Color.secondary.opacity(0.08))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isFocusedHere ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2),
                                    lineWidth: isFocusedHere ? 1.5 : 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isHandlingMove)
                    .onHover { hovering in
                        hoveredDisplayID = hovering ? display.id : nil
                    }
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
