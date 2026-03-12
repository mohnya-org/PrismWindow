import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect

    var isBuiltIn: Bool {
        CGDisplayIsBuiltin(id) != 0
    }

    static func availableDisplays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let id = CGDirectDisplayID(number.uint32Value)
            let fallbackName = screen.localizedName.isEmpty ? "Display \(id)" : screen.localizedName
            return DisplayInfo(
                id: id,
                name: fallbackName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
        .sorted {
            if $0.frame.minX == $1.frame.minX {
                return $0.frame.minY < $1.frame.minY
            }
            return $0.frame.minX < $1.frame.minX
        }
    }
}
