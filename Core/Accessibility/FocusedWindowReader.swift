@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation
import DeskPinsPinned

public enum FocusedWindowReadError: Error, Sendable, Equatable, CustomStringConvertible {
    case accessibilityNotTrusted
    case noFrontmostApplication
    case noFocusedWindow
    case unsupportedValue(String)
    case axError(String)

    public var description: String {
        switch self {
        case .accessibilityNotTrusted:
            return "Accessibility permission is not granted."
        case .noFrontmostApplication:
            return "No frontmost application is available."
        case .noFocusedWindow:
            return "No focused window is currently available."
        case .unsupportedValue(let detail):
            return "Accessibility returned an unsupported value: \(detail)"
        case .axError(let detail):
            return "Accessibility API failure: \(detail)"
        }
    }
}

public protocol FocusedWindowReading: Sendable {
    func currentFocusedWindow() throws -> FocusedWindowSnapshot
}

public struct LiveFocusedWindowReader: FocusedWindowReading {
    private let trustChecker: any AccessibilityTrustChecking

    public init(trustChecker: any AccessibilityTrustChecking = LiveAccessibilityTrustChecker()) {
        self.trustChecker = trustChecker
    }

    public func currentFocusedWindow() throws -> FocusedWindowSnapshot {
        guard trustChecker.currentStatus() == .trusted else {
            throw FocusedWindowReadError.accessibilityNotTrusted
        }

        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            throw FocusedWindowReadError.noFrontmostApplication
        }

        let applicationName = frontmostApplication.localizedName ?? "Unknown App"
        let appElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)

        guard let focusedWindowElement = try copyAXElement(
            attribute: kAXFocusedWindowAttribute,
            from: appElement
        ) else {
            throw FocusedWindowReadError.noFocusedWindow
        }

        let title = try copyOptionalString(
            attribute: kAXTitleAttribute,
            from: focusedWindowElement
        ) ?? ""
        let windowNumber = try copyOptionalInt(
            attribute: "AXWindowNumber",
            from: focusedWindowElement
        )

        let bounds = try readBounds(from: focusedWindowElement)

        return FocusedWindowSnapshot(
            ownerPID: frontmostApplication.processIdentifier,
            applicationName: applicationName,
            windowTitle: title,
            windowNumber: windowNumber,
            bounds: bounds
        )
    }

    private func copyAXElement(
        attribute: String,
        from element: AXUIElement
    ) throws -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        switch result {
        case .success:
            return value.map { unsafeDowncast($0, to: AXUIElement.self) }
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw FocusedWindowReadError.axError("\(result.rawValue) while reading \(attribute)")
        }
    }

    private func copyOptionalString(
        attribute: String,
        from element: AXUIElement
    ) throws -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        switch result {
        case .success:
            guard let string = value as? String else {
                return nil
            }

            return string
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw FocusedWindowReadError.axError("\(result.rawValue) while reading \(attribute)")
        }
    }

    private func copyOptionalInt(
        attribute: String,
        from element: AXUIElement
    ) throws -> Int? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        switch result {
        case .success:
            guard let number = value as? NSNumber else {
                return nil
            }
            return number.intValue
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw FocusedWindowReadError.axError("\(result.rawValue) while reading \(attribute)")
        }
    }

    private func readBounds(from element: AXUIElement) throws -> PinnedWindowBounds? {
        let position = try copyPoint(attribute: kAXPositionAttribute, from: element)
        let size = try copySize(attribute: kAXSizeAttribute, from: element)

        guard let position, let size else {
            return nil
        }

        return PinnedWindowBounds(
            x: Double(position.x),
            y: Double(position.y),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    private func copyPoint(
        attribute: String,
        from element: AXUIElement
    ) throws -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        switch result {
        case .success:
            guard let axValue = value else {
                return nil
            }

            return try decodeCGPoint(axValue, attributeName: attribute as String)
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw FocusedWindowReadError.axError("\(result.rawValue) while reading \(attribute)")
        }
    }

    private func copySize(
        attribute: String,
        from element: AXUIElement
    ) throws -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)

        switch result {
        case .success:
            guard let axValue = value else {
                return nil
            }

            return try decodeCGSize(axValue, attributeName: attribute as String)
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw FocusedWindowReadError.axError("\(result.rawValue) while reading \(attribute)")
        }
    }

    private func decodeCGPoint(_ value: CFTypeRef, attributeName: String) throws -> CGPoint? {
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            throw FocusedWindowReadError.unsupportedValue(attributeName)
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            throw FocusedWindowReadError.unsupportedValue(attributeName)
        }

        return point
    }

    private func decodeCGSize(_ value: CFTypeRef, attributeName: String) throws -> CGSize? {
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            throw FocusedWindowReadError.unsupportedValue(attributeName)
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            throw FocusedWindowReadError.unsupportedValue(attributeName)
        }

        return size
    }
}

public struct StaticFocusedWindowReader: FocusedWindowReading {
    public let snapshot: FocusedWindowSnapshot

    public init(snapshot: FocusedWindowSnapshot) {
        self.snapshot = snapshot
    }

    public func currentFocusedWindow() throws -> FocusedWindowSnapshot {
        snapshot
    }
}
