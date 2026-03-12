import ApplicationServices

enum AXErrorWrapper: LocalizedError {
    case failure(String)

    var errorDescription: String? {
        switch self {
        case .failure(let message):
            return message
        }
    }
}

extension AXUIElement {
    func value(for attribute: CFString) throws -> AnyObject {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self, attribute, &value)
        guard error == .success, let value else {
            throw AXErrorWrapper.failure("AX read failed for \(attribute).")
        }
        return value
    }

    func optionalValue(for attribute: CFString) -> AnyObject? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(self, attribute, &value)
        guard error == .success else {
            return nil
        }
        return value
    }

    func setValue(_ value: CFTypeRef, for attribute: CFString) throws {
        let error = AXUIElementSetAttributeValue(self, attribute, value)
        guard error == .success else {
            throw AXErrorWrapper.failure("AX write failed for \(attribute).")
        }
    }
}

func pointValue(_ point: CGPoint) -> AXValue {
    var point = point
    return AXValueCreate(.cgPoint, &point)!
}

func sizeValue(_ size: CGSize) -> AXValue {
    var size = size
    return AXValueCreate(.cgSize, &size)!
}

func cgPoint(from object: AnyObject?) -> CGPoint? {
    guard let object else {
        return nil
    }
    let value = unsafeDowncast(object, to: AXValue.self)
    guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value) == .cgPoint else {
        return nil
    }
    var point = CGPoint.zero
    return AXValueGetValue(value, .cgPoint, &point) ? point : nil
}

func cgSize(from object: AnyObject?) -> CGSize? {
    guard let object else {
        return nil
    }
    let value = unsafeDowncast(object, to: AXValue.self)
    guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value) == .cgSize else {
        return nil
    }
    var size = CGSize.zero
    return AXValueGetValue(value, .cgSize, &size) ? size : nil
}
