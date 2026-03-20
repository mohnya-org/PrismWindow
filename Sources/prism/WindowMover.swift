import AppKit
import ApplicationServices

struct MoveResult {
    let message: String
}

enum WindowMoveError: LocalizedError {
    case noFrontmostApp
    case ownAppWindow
    case noFocusedWindow
    case displayNotFound
    case unsupportedWindow

    var errorDescription: String? {
        switch self {
        case .noFrontmostApp:
            return "No frontmost app found."
        case .ownAppWindow:
            return "Prism's own windows cannot be moved."
        case .noFocusedWindow:
            return "The frontmost app does not expose a focused window."
        case .displayNotFound:
            return "The target display is not available."
        case .unsupportedWindow:
            return "The focused window could not be moved."
        }
    }
}

struct WindowMover {
    func focusedWindowMatches(displayID: CGDirectDisplayID, mode: DisplayWindowMode) throws -> Bool {
        let displays = DisplayInfo.availableDisplays()
        guard let target = displays.first(where: { $0.id == displayID }) else {
            throw WindowMoveError.displayNotFound
        }

        let context = try focusedWindowContext()
        let current = displayForWindowFrame(context.frame, displays: displays) ?? target
        guard current.id == target.id else {
            return false
        }

        switch mode {
        case .keepCurrent:
            return true
        case .fullscreen:
            return context.isFullScreen
        case .windowed:
            return !context.isFullScreen
        }
    }


    func moveFocusedWindow(to displayID: CGDirectDisplayID, mode: DisplayWindowMode = .keepCurrent) async throws -> MoveResult {
        let displays = DisplayInfo.availableDisplays()
        guard let target = displays.first(where: { $0.id == displayID }) else {
            throw WindowMoveError.displayNotFound
        }
        let context = try focusedWindowContext()
        let current = displayForWindowFrame(context.frame, displays: displays) ?? target
        let requiresModeChange = switch mode {
        case .keepCurrent:
            false
        case .fullscreen:
            !context.isFullScreen
        case .windowed:
            context.isFullScreen
        }

        guard current.id != target.id || requiresModeChange else {
            return MoveResult(message: "Already on \(target.name).")
        }
        return try await move(window: context.window, from: context.frame, to: target, mode: mode)
    }

    private func focusedWindowContext() throws -> (window: AXUIElement, frame: CGRect, isFullScreen: Bool) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowMoveError.noFrontmostApp
        }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw WindowMoveError.ownAppWindow
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedWindowObject = appElement.optionalValue(for: kAXFocusedWindowAttribute as CFString)
        guard let focusedWindowObject, CFGetTypeID(focusedWindowObject) == AXUIElementGetTypeID() else {
            throw WindowMoveError.noFocusedWindow
        }
        let focusedWindow = unsafeDowncast(focusedWindowObject, to: AXUIElement.self)

        guard let position = cgPoint(from: focusedWindow.optionalValue(for: kAXPositionAttribute as CFString)),
              let size = cgSize(from: focusedWindow.optionalValue(for: kAXSizeAttribute as CFString)) else {
            throw WindowMoveError.unsupportedWindow
        }

        let isFullScreen = (focusedWindow.optionalValue(for: fullScreenAttribute()) as? NSNumber)?.boolValue ?? false
        return (focusedWindow, CGRect(origin: position, size: size), isFullScreen)
    }

    private func move(window: AXUIElement, from frame: CGRect, to targetDisplay: DisplayInfo, mode: DisplayWindowMode) async throws -> MoveResult {
        let wasFullScreen = (window.optionalValue(for: fullScreenAttribute()) as? NSNumber)?.boolValue ?? false
        let app = NSWorkspace.shared.frontmostApplication
        let displays = DisplayInfo.availableDisplays()
        let sourceDisplay = displayForWindowFrame(frame, displays: displays) ?? targetDisplay
        let shouldEndFullScreen = switch mode {
        case .keepCurrent:
            wasFullScreen
        case .windowed:
            wasFullScreen
        case .fullscreen:
            wasFullScreen
        }
        let shouldEnterFullScreen = switch mode {
        case .keepCurrent:
            wasFullScreen
        case .windowed:
            false
        case .fullscreen:
            true
        }

        if shouldEndFullScreen {
            // Hide the app and wait until macOS confirms it is hidden, so that
            // the fullscreen-exit space transition plays over an empty window.
            app?.hide()
            if let app {
                for _ in 0..<20 {
                    if app.isHidden { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
            }

            try window.setValue(kCFBooleanFalse, for: fullScreenAttribute())
            try await waitForFullScreenState(of: window, expected: false)
            // The AX attribute flips before the space-transition animation
            // finishes. Wait for the actual animation to complete.
            try await waitForSpaceChange()
            // Give the compositor a few extra frames to flush the source
            // display's framebuffer after the space transition completes.
            try await Task.sleep(for: .milliseconds(200))

            // Push the window just outside the source display's
            // visible area. This clears any stale snapshot / residual image
            // that macOS leaves behind after the fullscreen-exit animation.
            let hidePoint = CGPoint(
                x: sourceDisplay.frame.maxX + 100,
                y: sourceDisplay.frame.maxY + 100
            )
            try window.setValue(pointValue(hidePoint), for: kAXPositionAttribute as CFString)
            let tinySize = CGSize(width: 1, height: 1)
            try window.setValue(sizeValue(tinySize), for: kAXSizeAttribute as CFString)
        }

        let targetRect = targetDisplay.visibleFrame.insetBy(dx: 20, dy: 20)
        try window.setValue(pointValue(targetRect.origin), for: kAXPositionAttribute as CFString)
        try window.setValue(sizeValue(targetRect.size), for: kAXSizeAttribute as CFString)

        if shouldEnterFullScreen {
            try window.setValue(kCFBooleanTrue, for: fullScreenAttribute())
            try await waitForFullScreenState(of: window, expected: true)
            // Wait for the fullscreen-enter animation to complete before
            // showing the app, so the user never sees the windowed state.
            try await waitForSpaceChange()
            app?.unhide()
            app?.activate()
            return MoveResult(message: "Moved window to \(targetDisplay.name) in fullscreen.")
        }

        let targetName = targetDisplay.name
        let sourceName = displayForWindowFrame(frame, displays: DisplayInfo.availableDisplays())?.name ?? "current display"
        return MoveResult(message: "Moved window from \(sourceName) to \(targetName).")
    }

    private func waitForFullScreenState(of window: AXUIElement, expected: Bool) async throws {
        for _ in 0..<30 {
            let current = (window.optionalValue(for: fullScreenAttribute()) as? NSNumber)?.boolValue ?? false
            if current == expected {
                return
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        throw WindowMoveError.unsupportedWindow
    }

    private func waitForSpaceChange(timeout: Duration = .seconds(3)) async throws {
        let center = NSWorkspace.shared.notificationCenter
        let notifications = center.notifications(
            named: NSWorkspace.activeSpaceDidChangeNotification
        )
        // Wait for the first notification or give up after the timeout.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in notifications { break }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func fullScreenAttribute() -> CFString {
        "AXFullScreen" as CFString
    }

    private func displayForWindowFrame(_ frame: CGRect, displays: [DisplayInfo]) -> DisplayInfo? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let containing = displays.first(where: { $0.frame.contains(center) }) {
            return containing
        }

        return displays.max { lhs, rhs in
            lhs.frame.intersection(frame).area < rhs.frame.intersection(frame).area
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
