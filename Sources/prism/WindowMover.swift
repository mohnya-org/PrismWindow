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
            return "Prism Window's own windows cannot be moved."
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
        // Wait for any in-progress animation (minimize, zoom, etc.) to settle.
        // The window frame keeps changing during animations, so we poll until
        // two consecutive reads return the same position and size.
        try await waitForWindowToSettle(window)

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
        let shouldHideTransition = shouldEndFullScreen && shouldEnterFullScreen
        var shouldRestoreHiddenApp = false
        defer {
            if shouldRestoreHiddenApp {
                app?.unhide()
                app?.activate()
            }
        }

        if shouldEndFullScreen {
            if shouldHideTransition {
                // Hide only when the window will return to fullscreen. If the
                // final state is windowed, hiding can leave macOS showing the
                // old fullscreen snapshot on the source display.
                app?.hide()
                shouldRestoreHiddenApp = true
            }

            if let app, shouldHideTransition {
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

            if shouldHideTransition {
                // While hidden, move the window out of the source display
                // before resizing it on the target display.
                let hidePoint = CGPoint(
                    x: sourceDisplay.frame.maxX + 100,
                    y: sourceDisplay.frame.maxY + 100
                )
                try window.setValue(pointValue(hidePoint), for: kAXPositionAttribute as CFString)
                let tinySize = CGSize(width: 1, height: 1)
                try window.setValue(sizeValue(tinySize), for: kAXSizeAttribute as CFString)
            }
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
            shouldRestoreHiddenApp = false
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

    /// Poll until the window's frame stops changing, indicating that any
    /// in-progress animation (minimize restore, zoom, space transition, etc.)
    /// has finished. Throws after a timeout to avoid hanging indefinitely.
    private func waitForWindowToSettle(_ window: AXUIElement) async throws {
        let isMinimized = (window.optionalValue(for: kAXMinimizedAttribute as CFString) as? NSNumber)?.boolValue ?? false
        if isMinimized {
            // Cannot move a minimized window — wait for it to be restored.
            for _ in 0..<50 {
                let still = (window.optionalValue(for: kAXMinimizedAttribute as CFString) as? NSNumber)?.boolValue ?? false
                if !still { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            // Extra grace period for the restore animation.
            try await Task.sleep(for: .milliseconds(300))
        }

        var previousFrame: CGRect?
        for _ in 0..<30 {
            let pos = cgPoint(from: window.optionalValue(for: kAXPositionAttribute as CFString))
            let size = cgSize(from: window.optionalValue(for: kAXSizeAttribute as CFString))
            if let pos, let size {
                let current = CGRect(origin: pos, size: size)
                if let prev = previousFrame, prev.equalTo(current) {
                    return
                }
                previousFrame = current
            }
            try await Task.sleep(for: .milliseconds(80))
        }
        // Timed out — proceed anyway; the move may still succeed.
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
