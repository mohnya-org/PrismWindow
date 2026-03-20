import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect

    var isBuiltIn: Bool {
        CGDisplayIsBuiltin(id) != 0
    }

    var persistentID: String {
        let rect = frame.integral
        return "\(name)|\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
    }

    static func availableDisplays() -> [DisplayInfo] {
        // NSScreen uses bottom-left origin (Y up), but AX APIs use
        // top-left origin (Y down). Convert all frames to AX coordinates.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let id = CGDirectDisplayID(number.uint32Value)
            let fallbackName = screen.localizedName.isEmpty ? "Display \(id)" : screen.localizedName
            return DisplayInfo(
                id: id,
                name: fallbackName,
                frame: nsRectToCG(screen.frame, primaryHeight: primaryHeight),
                visibleFrame: nsRectToCG(screen.visibleFrame, primaryHeight: primaryHeight)
            )
        }
        .sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.frame.minY < $1.frame.minY
            }
            return $0.frame.minX < $1.frame.minX
        }
    }

    private static func nsRectToCG(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    static func currentLayoutSignature(for displays: [DisplayInfo]) -> String {
        displays.map(\.persistentID).joined(separator: "||")
    }
}
