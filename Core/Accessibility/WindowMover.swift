@preconcurrency import ApplicationServices
import Foundation
import DeskPinsPinned

public enum WindowMoveError: Error, Sendable, Equatable, CustomStringConvertible {
    case accessibilityNotTrusted
    case noMatchingWindow
    case noWindowPosition
    case axError(String)

    public var description: String {
        switch self {
        case .accessibilityNotTrusted:
            return "Accessibility permission is not granted."
        case .noMatchingWindow:
            return "DeskPins could not find a matching window to move."
        case .noWindowPosition:
            return "DeskPins could not read the current window position."
        case .axError(let detail):
            return "Accessibility API failure while moving the window: \(detail)"
        }
    }
}

public struct WindowMoveDragSession: Sendable, Equatable {
    public var id: UUID
    public var reference: PinnedWindowReference

    public init(
        id: UUID = UUID(),
        reference: PinnedWindowReference
    ) {
        self.id = id
        self.reference = reference
    }
}

public protocol WindowMoving: Sendable {
    func beginDragSession(
        for reference: PinnedWindowReference
    ) throws -> WindowMoveDragSession
    func moveWindow(
        in session: WindowMoveDragSession,
        deltaX: Double,
        deltaY: Double
    ) throws
    func endDragSession(_ session: WindowMoveDragSession)
    func moveWindow(
        reference: PinnedWindowReference,
        deltaX: Double,
        deltaY: Double
    ) throws
}

public struct NoopWindowMover: WindowMoving {
    public init() {}

    public func beginDragSession(
        for reference: PinnedWindowReference
    ) throws -> WindowMoveDragSession {
        WindowMoveDragSession(reference: reference)
    }

    public func moveWindow(
        in session: WindowMoveDragSession,
        deltaX: Double,
        deltaY: Double
    ) throws {}

    public func endDragSession(_ session: WindowMoveDragSession) {}

    public func moveWindow(
        reference: PinnedWindowReference,
        deltaX: Double,
        deltaY: Double
    ) throws {}
}

public struct LiveWindowMover: WindowMoving {
    private let trustChecker: any AccessibilityTrustChecking
    private let sessionStore = WindowMoveSessionStore.shared

    public init(trustChecker: any AccessibilityTrustChecking = LiveAccessibilityTrustChecker()) {
        self.trustChecker = trustChecker
    }

    public func beginDragSession(
        for reference: PinnedWindowReference
    ) throws -> WindowMoveDragSession {
        guard trustChecker.currentStatus() == .trusted else {
            throw WindowMoveError.accessibilityNotTrusted
        }

        let applicationElement = AXUIElementCreateApplication(reference.ownerPID)
        guard let windowElement = try findMatchingWindow(
            reference: reference,
            in: applicationElement
        ) else {
            throw WindowMoveError.noMatchingWindow
        }

        let session = WindowMoveDragSession(reference: reference)
        sessionStore.setWindowElement(windowElement, for: session.id)
        return session
    }

    public func moveWindow(
        in session: WindowMoveDragSession,
        deltaX: Double,
        deltaY: Double
    ) throws {
        guard trustChecker.currentStatus() == .trusted else {
            throw WindowMoveError.accessibilityNotTrusted
        }

        if let windowElement = sessionStore.windowElement(for: session.id) {
            do {
                try move(
                    windowElement: windowElement,
                    deltaX: deltaX,
                    deltaY: deltaY
                )
                return
            } catch {}
        }

        let applicationElement = AXUIElementCreateApplication(session.reference.ownerPID)
        guard let windowElement = try findMatchingWindow(
            reference: session.reference,
            in: applicationElement
        ) else {
            throw WindowMoveError.noMatchingWindow
        }

        sessionStore.setWindowElement(windowElement, for: session.id)
        try move(
            windowElement: windowElement,
            deltaX: deltaX,
            deltaY: deltaY
        )
    }

    public func endDragSession(_ session: WindowMoveDragSession) {
        sessionStore.removeWindowElement(for: session.id)
    }

    public func moveWindow(
        reference: PinnedWindowReference,
        deltaX: Double,
        deltaY: Double
    ) throws {
        guard trustChecker.currentStatus() == .trusted else {
            throw WindowMoveError.accessibilityNotTrusted
        }

        let applicationElement = AXUIElementCreateApplication(reference.ownerPID)
        guard let windowElement = try findMatchingWindow(
            reference: reference,
            in: applicationElement
        ) else {
            throw WindowMoveError.noMatchingWindow
        }

        guard var position = try readPosition(from: windowElement) else {
            throw WindowMoveError.noWindowPosition
        }

        position.x += deltaX
        position.y += deltaY
        try setPosition(position, for: windowElement)
    }

    private func move(
        windowElement: AXUIElement,
        deltaX: Double,
        deltaY: Double
    ) throws {
        guard var position = try readPosition(from: windowElement) else {
            throw WindowMoveError.noWindowPosition
        }

        position.x += deltaX
        position.y += deltaY
        try setPosition(position, for: windowElement)
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
            throw WindowMoveError.axError(
                "\(result.rawValue) while reading app windows"
            )
        }
    }

    private func copyAXElement(
        attribute: String,
        from element: AXUIElement
    ) throws -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        switch result {
        case .success:
            return value.map { unsafeDowncast($0, to: AXUIElement.self) }
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw WindowMoveError.axError(
                "\(result.rawValue) while reading \(attribute)"
            )
        }
    }

    private func copyOptionalString(
        attribute: String,
        from element: AXUIElement
    ) throws -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        switch result {
        case .success:
            return value as? String
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw WindowMoveError.axError(
                "\(result.rawValue) while reading \(attribute)"
            )
        }
    }

    private func copyOptionalInt(
        attribute: String,
        from element: AXUIElement
    ) throws -> Int? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        switch result {
        case .success:
            guard let number = value as? NSNumber else {
                return nil
            }
            return number.intValue
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw WindowMoveError.axError(
                "\(result.rawValue) while reading \(attribute)"
            )
        }
    }

    private func readBounds(from element: AXUIElement) throws -> PinnedWindowBounds? {
        let position = try readPosition(from: element)
        let size = try copySize(from: element)

        guard let position, let size else {
            return nil
        }

        return PinnedWindowBounds(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }

    private func readPosition(from element: AXUIElement) throws -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &value
        )

        switch result {
        case .success:
            guard let value else {
                return nil
            }

            let axValue = unsafeDowncast(value, to: AXValue.self)
            guard AXValueGetType(axValue) == .cgPoint else {
                throw WindowMoveError.axError("unsupported point value for AXPosition")
            }

            var point = CGPoint.zero
            guard AXValueGetValue(axValue, .cgPoint, &point) else {
                throw WindowMoveError.axError("unable to decode point value for AXPosition")
            }
            return point
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw WindowMoveError.axError(
                "\(result.rawValue) while reading AXPosition"
            )
        }
    }

    private func copySize(from element: AXUIElement) throws -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &value
        )

        switch result {
        case .success:
            guard let value else {
                return nil
            }

            let axValue = unsafeDowncast(value, to: AXValue.self)
            guard AXValueGetType(axValue) == .cgSize else {
                throw WindowMoveError.axError("unsupported size value for AXSize")
            }

            var size = CGSize.zero
            guard AXValueGetValue(axValue, .cgSize, &size) else {
                throw WindowMoveError.axError("unable to decode size value for AXSize")
            }
            return size
        case .noValue, .attributeUnsupported:
            return nil
        default:
            throw WindowMoveError.axError(
                "\(result.rawValue) while reading AXSize"
            )
        }
    }

    private func setPosition(_ point: CGPoint, for element: AXUIElement) throws {
        var mutablePoint = point
        guard let pointValue = AXValueCreate(.cgPoint, &mutablePoint) else {
            throw WindowMoveError.axError("unable to create AX point value for AXPosition")
        }

        let result = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            pointValue
        )
        if result != .success {
            throw WindowMoveError.axError(
                "\(result.rawValue) while setting AXPosition"
            )
        }
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
        abs(lhs.x - rhs.x) <= 32 &&
        abs(lhs.y - rhs.y) <= 32 &&
        abs(lhs.width - rhs.width) <= 64 &&
        abs(lhs.height - rhs.height) <= 64
    }
}

private final class WindowMoveSessionStore: @unchecked Sendable {
    static let shared = WindowMoveSessionStore()

    private var windowElementsBySessionID: [UUID: AXUIElement] = [:]
    private let lock = NSLock()

    private init() {}

    func setWindowElement(_ element: AXUIElement, for id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        windowElementsBySessionID[id] = element
    }

    func windowElement(for id: UUID) -> AXUIElement? {
        lock.lock()
        defer { lock.unlock() }
        return windowElementsBySessionID[id]
    }

    func removeWindowElement(for id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        windowElementsBySessionID[id] = nil
    }
}
