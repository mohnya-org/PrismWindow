import AppKit
import ApplicationServices

struct MoveResult {
    let message: String
}

enum WindowMoveError: LocalizedError {
    case noDisplays
    case noFrontmostApp
    case noFocusedWindow
    case displayNotFound
    case unsupportedWindow

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            return "No secondary display is available."
        case .noFrontmostApp:
            return "No frontmost app found."
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
    func moveFocusedWindowToNextDisplay() async throws -> MoveResult {
        let displays = DisplayInfo.availableDisplays()
        guard displays.count > 1 else {
            throw WindowMoveError.noDisplays
        }

        let context = try focusedWindowContext()
        let currentDisplay = displayForWindowFrame(context.frame, displays: displays) ?? displays[0]
        guard let currentIndex = displays.firstIndex(where: { $0.id == currentDisplay.id }) else {
            throw WindowMoveError.displayNotFound
        }
        let nextDisplay = displays[(currentIndex + 1) % displays.count]
        return try await move(window: context.window, from: context.frame, to: nextDisplay)
    }

    func moveFocusedWindow(to displayID: CGDirectDisplayID) async throws -> MoveResult {
        let displays = DisplayInfo.availableDisplays()
        guard let target = displays.first(where: { $0.id == displayID }) else {
            throw WindowMoveError.displayNotFound
        }
        let context = try focusedWindowContext()
        let current = displayForWindowFrame(context.frame, displays: displays) ?? target
        guard current.id != target.id else {
            return MoveResult(message: "Already on \(target.name).")
        }
        return try await move(window: context.window, from: context.frame, to: target)
    }

    private func focusedWindowContext() throws -> (window: AXUIElement, frame: CGRect, isFullScreen: Bool) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowMoveError.noFrontmostApp
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

    private func move(window: AXUIElement, from frame: CGRect, to targetDisplay: DisplayInfo) async throws -> MoveResult {
        let wasFullScreen = (window.optionalValue(for: fullScreenAttribute()) as? NSNumber)?.boolValue ?? false

        if wasFullScreen {
            try window.setValue(kCFBooleanFalse, for: fullScreenAttribute())
            try await waitForFullScreenState(of: window, expected: false)
        }

        let targetRect = targetDisplay.visibleFrame.insetBy(dx: 20, dy: 20)
        try window.setValue(pointValue(targetRect.origin), for: kAXPositionAttribute as CFString)
        try window.setValue(sizeValue(targetRect.size), for: kAXSizeAttribute as CFString)

        try await Task.sleep(for: .milliseconds(250))

        if wasFullScreen {
            try window.setValue(kCFBooleanTrue, for: fullScreenAttribute())
            try await waitForFullScreenState(of: window, expected: true)
            return MoveResult(message: "Moved fullscreen window to \(targetDisplay.name) via fallback.")
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
