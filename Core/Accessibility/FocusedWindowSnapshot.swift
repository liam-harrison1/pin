@preconcurrency import AppKit
import Foundation
import DeskPinsPinned

public struct FocusedWindowSnapshot: Sendable, Equatable, Codable {
    public var ownerPID: Int32
    public var applicationName: String
    public var windowTitle: String
    public var bounds: PinnedWindowBounds?
    public var capturedAt: Date

    public init(
        ownerPID: Int32,
        applicationName: String,
        windowTitle: String,
        bounds: PinnedWindowBounds? = nil,
        capturedAt: Date = .now
    ) {
        self.ownerPID = ownerPID
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.bounds = bounds
        self.capturedAt = capturedAt
    }

    public var effectiveTitle: String {
        let trimmedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let trimmedAppName = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAppName.isEmpty {
            return trimmedAppName
        }

        return "Window \(ownerPID)"
    }

    public func asPinnedReference() -> PinnedWindowReference {
        PinnedWindowReference(
            ownerPID: ownerPID,
            windowTitle: effectiveTitle,
            bounds: bounds
        )
    }
}
