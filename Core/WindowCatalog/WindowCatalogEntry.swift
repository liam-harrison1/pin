import Foundation
import DeskPinsPinned

public struct WindowCatalogEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var frontToBackIndex: Int
    public var ownerPID: Int32
    public var ownerName: String
    public var windowTitle: String
    public var windowNumber: Int?
    public var layer: Int
    public var alpha: Double
    public var bounds: WindowCatalogBounds
    public var isOnScreen: Bool

    public init(
        id: UUID = UUID(),
        frontToBackIndex: Int,
        ownerPID: Int32,
        ownerName: String,
        windowTitle: String,
        windowNumber: Int? = nil,
        layer: Int,
        alpha: Double,
        bounds: WindowCatalogBounds,
        isOnScreen: Bool
    ) {
        self.id = id
        self.frontToBackIndex = frontToBackIndex
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.windowNumber = windowNumber
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
        self.isOnScreen = isOnScreen
    }

    public var effectiveTitle: String {
        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? ownerName : trimmedTitle
    }

    public var searchTokens: [String] {
        [ownerName, windowTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func asPinnedReference() -> PinnedWindowReference {
        PinnedWindowReference(
            ownerPID: ownerPID,
            windowTitle: effectiveTitle,
            windowNumber: windowNumber,
            bounds: PinnedWindowBounds(
                x: bounds.x,
                y: bounds.y,
                width: bounds.width,
                height: bounds.height
            )
        )
    }
}
