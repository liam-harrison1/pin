import Foundation

public struct WindowCatalogPoint: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct WindowCatalogBounds: Sendable, Equatable, Codable {
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

    public var hasArea: Bool {
        width > 0 && height > 0
    }

    public func contains(_ point: WindowCatalogPoint) -> Bool {
        guard hasArea else {
            return false
        }

        let maxX = x + width
        let maxY = y + height
        return point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
    }
}
