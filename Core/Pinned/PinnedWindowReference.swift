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

        if let windowNumber, let otherWindowNumber = other.windowNumber {
            return windowNumber == otherWindowNumber
        }

        if windowTitle != other.windowTitle {
            return false
        }

        if let bounds, let otherBounds = other.bounds {
            return bounds == otherBounds
        }

        return true
    }
}
