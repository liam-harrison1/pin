import Foundation

public struct PinnedWindowBounds: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PinnedWindowReference: Sendable, Equatable, Codable {
    public var ownerPID: Int32
    public var windowTitle: String
    public var windowNumber: Int?
    public var bounds: PinnedWindowBounds?

    public init(
        ownerPID: Int32,
        windowTitle: String,
        windowNumber: Int? = nil,
        bounds: PinnedWindowBounds? = nil
    ) {
        self.ownerPID = ownerPID
        self.windowTitle = windowTitle
        self.windowNumber = windowNumber
        self.bounds = bounds
    }

    public func likelyMatches(_ other: PinnedWindowReference) -> Bool {
        guard ownerPID == other.ownerPID else {
            return false
        }

        if matchingWindowNumbers(with: other) {
            // windowNumber can be recycled by the window server within a
            // long-lived process; require approximate bounds as a sanity check.
            if let bounds, let otherBounds = other.bounds {
                let manhattan = abs(bounds.x - otherBounds.x)
                    + abs(bounds.y - otherBounds.y)
                    + abs(bounds.width - otherBounds.width)
                    + abs(bounds.height - otherBounds.height)
                if manhattan > 400 { return false }
            }
            return true
        }

        let normalizedTitle = Self.normalizedTitle(windowTitle)
        let normalizedOtherTitle = Self.normalizedTitle(other.windowTitle)
        let titleMatches = !normalizedTitle.isEmpty && normalizedTitle == normalizedOtherTitle
        let boundsMatch = Self.approximatelyMatches(bounds, other.bounds)
        let missingWindowNumber = windowNumber == nil || other.windowNumber == nil
        let bothHaveBounds = bounds != nil && other.bounds != nil
        let hasUntitledSide = normalizedTitle.isEmpty || normalizedOtherTitle.isEmpty

        if titleMatches && boundsMatch {
            return true
        }

        if titleMatches && missingWindowNumber {
            if bothHaveBounds && !boundsMatch {
                return false
            }
            return true
        }

        if boundsMatch && missingWindowNumber && hasUntitledSide {
            return true
        }

        return false
    }

    private func matchingWindowNumbers(with other: PinnedWindowReference) -> Bool {
        guard let windowNumber, let otherWindowNumber = other.windowNumber else {
            return false
        }

        return windowNumber == otherWindowNumber
    }

    private static func normalizedTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func approximatelyMatches(
        _ leftBounds: PinnedWindowBounds?,
        _ rightBounds: PinnedWindowBounds?
    ) -> Bool {
        guard let leftBounds, let rightBounds else {
            return false
        }

        return abs(leftBounds.x - rightBounds.x) <= 40 &&
            abs(leftBounds.y - rightBounds.y) <= 40 &&
            abs(leftBounds.width - rightBounds.width) <= 80 &&
            abs(leftBounds.height - rightBounds.height) <= 80
    }
}
