import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var hoveredDisplay: DisplayInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Prism")
                    .font(.title2.bold())
                Spacer()
                Toggle(isOn: launchAtLoginBinding) {
                    Text("Launch at Login")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        )
    }

    private var displayLayout: some View {
        let displays = DisplayInfo.availableDisplays()

        return VStack(alignment: .leading, spacing: 6) {
            Label("Click a display to move the focused window", systemImage: "rectangle.2.swap")
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
                    isFocusedAppRuleCompliant: isFocusedAppRuleCompliant,
                    hoveredDisplay: $hoveredDisplay,
                    onSelect: moveFocusedWindow(to:)
                )
                .frame(height: 200)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Detail bar below the layout
                displayDetailBar(displays: displays)
            }
        }
    }

    private func displayDetailBar(displays: [DisplayInfo]) -> some View {
        let display = hoveredDisplay ?? displays.first(where: { isAppOnDisplay($0) })

        return HStack(spacing: 8) {
            if let display {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(display.name)
                    .font(.caption.weight(.semibold))
                Text("\(Int(display.frame.width))×\(Int(display.frame.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Hover over a display for details")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
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

    private var isFocusedAppRuleCompliant: Bool {
        guard appState.autoApplyRules,
              let bundleID = appState.currentAppDescriptor?.bundleIdentifier,
              appState.currentLayoutRules.contains(where: { $0.bundleIdentifier == bundleID }) else {
            return false
        }
        // If auto-apply is on and a rule exists, the app is either already
        // on the correct display or will be moved there momentarily.
        return true
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
    let isFocusedAppRuleCompliant: Bool
    @Binding var hoveredDisplay: DisplayInfo?
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
                    let isLocked = isFocusedHere && isFocusedAppRuleCompliant

                    DisplayTileButton(
                        display: display,
                        focusedApp: isFocusedHere ? focusedAppDescriptor : nil,
                        isHovered: isHovered,
                        isFocusedHere: isFocusedHere,
                        isLocked: isLocked,
                        tileFrame: frame,
                        isDisabled: isHandlingMove || isFocusedAppRuleCompliant,
                        onSelect: { onSelect(display.id) }
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredDisplayID = hovering ? display.id : nil
                            hoveredDisplay = hovering ? display : nil
                        }
                    }
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .clipped()
        .contentShape(Rectangle())
    }

}

private struct DisplayTileButton: View {
    let display: DisplayInfo
    let focusedApp: AppDescriptor?
    let isHovered: Bool
    let isFocusedHere: Bool
    let isLocked: Bool
    let tileFrame: CGRect
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                tileContent
            }
            .frame(width: tileFrame.width, height: tileFrame.height)
            .background { tileBackground }
            .overlay { tileBorder }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    @ViewBuilder
    private var tileContent: some View {
        if isHovered && !isLocked {
            hoverContent
        } else if isLocked, let app = focusedApp {
            lockedContent(app)
        } else if let app = focusedApp {
            appBadge(app)
        }
    }

    private var hoverContent: some View {
        VStack(spacing: 4) {
            Text(display.name)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if isFocusedHere {
                Label("Current display", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Label("Move here", systemImage: "arrow.right.circle")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(6)
    }

    private func lockedContent(_ app: AppDescriptor) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Text(app.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            Label("Rule applied", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func appBadge(_ app: AppDescriptor) -> some View {
        HStack(spacing: 6) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Text(app.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
    }

    private var tileBackground: some View {
        let fill: Color = isFocusedHere
            ? Color.accentColor.opacity(isHovered ? 0.18 : 0.1)
            : isHovered
                ? Color.secondary.opacity(0.18)
                : Color.secondary.opacity(0.08)
        return RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill)
    }

    private var tileBorder: some View {
        let stroke: Color = isFocusedHere
            ? Color.accentColor.opacity(0.5)
            : Color.secondary.opacity(isHovered ? 0.4 : 0.2)
        let width: CGFloat = isFocusedHere ? 1.5 : 1
        return RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: width)
    }
}

private extension MenuBarDisplayLayoutView {
    func isAppOnDisplay(_ display: DisplayInfo) -> Bool {
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
