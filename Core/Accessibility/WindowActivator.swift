@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation
import DeskPinsPinned

public enum WindowActivationError: Error, Sendable, Equatable, CustomStringConvertible {
    case accessibilityNotTrusted
    case applicationNotRunning(Int32)
    case noMatchingWindow
    case axError(String)

    public var description: String {
        switch self {
        case .accessibilityNotTrusted:
            return "Accessibility permission is not granted."
        case .applicationNotRunning(let pid):
            return "The target application is not running (pid \(pid))."
        case .noMatchingWindow:
            return "DeskPins could not find a matching window to bring forward."
        case .axError(let detail):
            return "Accessibility API failure while bringing the window forward: \(detail)"
        }
    }
}

public protocol WindowActivating: Sendable {
    func activateWindow(reference: PinnedWindowReference) throws
}

public struct NoopWindowActivator: WindowActivating {
    public init() {}

    public func activateWindow(reference: PinnedWindowReference) throws {}
}

public struct LiveWindowActivator: WindowActivating {
    private let trustChecker: any AccessibilityTrustChecking

    public init(trustChecker: any AccessibilityTrustChecking = LiveAccessibilityTrustChecker()) {
        self.trustChecker = trustChecker
    }

    public func activateWindow(reference: PinnedWindowReference) throws {
        guard trustChecker.currentStatus() == .trusted else {
            throw WindowActivationError.accessibilityNotTrusted
        }

        guard let application = NSRunningApplication(
            processIdentifier: reference.ownerPID
        ) else {
            throw WindowActivationError.applicationNotRunning(reference.ownerPID)
        }

        application.unhide()
        _ = application.activate(options: [])

        let applicationElement = AXUIElementCreateApplication(reference.ownerPID)
        guard let windowElement = try findMatchingWindow(
            reference: reference,
            in: applicationElement
        ) else {
            throw WindowActivationError.noMatchingWindow
        }

        let setFocusedResult = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            windowElement
        )
        if setFocusedResult != .success && setFocusedResult != .attributeUnsupported {
            throw WindowActivationError.axError(
                "\(setFocusedResult.rawValue) while setting focused window"
            )
        }

        let raiseResult = AXUIElementPerformAction(
            windowElement,
            kAXRaiseAction as CFString
        )
        if raiseResult != .success && raiseResult != .actionUnsupported {
            throw WindowActivationError.axError(
                "\(raiseResult.rawValue) while raising window"
            )
        }
    }

    private func findMatchingWindow(
        reference: PinnedWindowReference,
        in applicationElement: AXUIElement
    ) throws -> AXUIElement? {
        let windows = try copyWindowElements(from: applicationElement)
        if let windowNumber = reference.windowNumber,
           let exactWindow = windows.first(where: { candidate in
               (try? copyOptionalInt(
                   attribute: "AXWindowNumber",
                   from: candidate
               )) == windowNumber
           }) {
            return exactWindow
        }

        if let bestWindow = windows.max(by: { lhs, rhs in
            matchScore(for: lhs, reference: reference) < matchScore(for: rhs, reference: reference)
        }), matchScore(for: bestWindow, reference: reference) > 0 {
            return bestWindow
        }

        if windows.count == 1 {
            return windows.first
        }

        return try copyAXElement(
            attribute: kAXFocusedWindowAttribute,
            from: applicationElement
        )
    }

    private func copyWindowElements(from applicationElement: AXUIElement) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &value
        )

        switch result {
        case .success:
            return value as? [AXUIElement] ?? []
        case .noValue, .attributeUnsupported:
            return []
        default:
            throw WindowActivationError.axError(
                "\(result.rawValue) while reading app windows"
            )
        }
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
            throw WindowActivationError.axError(
                "\(result.rawValue) while reading \(attribute)"
            )
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
            return value as? String
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw WindowActivationError.axError(
                "\(result.rawValue) while reading \(attribute)"
            )
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
            throw WindowActivationError.axError(
                "\(result.rawValue) while reading \(attribute)"
            )
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
            return try decodeCGPoint(axValue, attributeName: attribute)
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw WindowActivationError.axError(
                "\(result.rawValue) while reading \(attribute)"
            )
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
            return try decodeCGSize(axValue, attributeName: attribute)
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw WindowActivationError.axError(
                "\(result.rawValue) while reading \(attribute)"
            )
        }
    }

    private func decodeCGPoint(_ value: CFTypeRef, attributeName: String) throws -> CGPoint? {
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgPoint else {
            throw WindowActivationError.axError("unsupported point value for \(attributeName)")
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            throw WindowActivationError.axError("unable to decode point value for \(attributeName)")
        }

        return point
    }

    private func decodeCGSize(_ value: CFTypeRef, attributeName: String) throws -> CGSize? {
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgSize else {
            throw WindowActivationError.axError("unsupported size value for \(attributeName)")
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            throw WindowActivationError.axError("unable to decode size value for \(attributeName)")
        }

        return size
    }

    private func matchScore(
        for element: AXUIElement,
        reference: PinnedWindowReference
    ) -> Int {
        let normalizedTitle = reference.windowTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let elementTitle = (try? copyOptionalString(
            attribute: kAXTitleAttribute,
            from: element
        ))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let elementBounds = try? readBounds(from: element)

        var score = 0

        if !normalizedTitle.isEmpty && normalizedTitle == elementTitle {
            score += 100
        }

        if let referenceBounds = reference.bounds,
           let elementBounds,
           boundsApproximatelyEqual(referenceBounds, elementBounds) {
            score += 25
        }

        if score == 0 && normalizedTitle.isEmpty && reference.bounds == nil {
            score = 1
        }

        return score
    }

    private func boundsApproximatelyEqual(
        _ lhs: PinnedWindowBounds,
        _ rhs: PinnedWindowBounds
    ) -> Bool {
        abs(lhs.x - rhs.x) <= 2 &&
        abs(lhs.y - rhs.y) <= 2 &&
        abs(lhs.width - rhs.width) <= 2 &&
        abs(lhs.height - rhs.height) <= 2
    }
}
