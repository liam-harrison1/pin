import Foundation

public struct PinnedWindow: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var reference: PinnedWindowReference
    public var lastPinnedAt: Date
    public var lastActivatedAt: Date?
    public var lastObservedAt: Date
    public var invalidation: PinnedWindowInvalidation?

    public init(
        id: UUID = UUID(),
        reference: PinnedWindowReference,
        lastPinnedAt: Date,
        lastActivatedAt: Date? = nil,
        lastObservedAt: Date? = nil,
        invalidation: PinnedWindowInvalidation? = nil
    ) {
        self.id = id
        self.reference = reference
        self.lastPinnedAt = lastPinnedAt
        self.lastActivatedAt = lastActivatedAt
        self.lastObservedAt = lastObservedAt ?? lastPinnedAt
        self.invalidation = invalidation
    }

    public var mostRecentRelevantDate: Date {
        lastActivatedAt ?? lastPinnedAt
    }

    public var ownerPID: Int32 {
        reference.ownerPID
    }

    public var windowTitle: String {
        reference.windowTitle
    }

    public var windowNumber: Int? {
        reference.windowNumber
    }

    public var bounds: PinnedWindowBounds? {
        reference.bounds
    }

    public var isInvalidated: Bool {
        invalidation != nil
    }
}
