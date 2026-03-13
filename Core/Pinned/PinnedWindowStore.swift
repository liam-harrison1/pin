import Foundation

public enum PinnedWindowInvalidationReason: String, Sendable, Equatable, Codable {
    case windowClosed
    case applicationExited
    case permissionLost
    case noLongerMatched
}

public struct PinnedWindowInvalidation: Sendable, Equatable, Codable {
    public var reason: PinnedWindowInvalidationReason
    public var invalidatedAt: Date

    public init(reason: PinnedWindowInvalidationReason, invalidatedAt: Date) {
        self.reason = reason
        self.invalidatedAt = invalidatedAt
    }
}

public struct PinnedWindowStore: Sendable {
    private var windowsByID: [UUID: PinnedWindow]

    public init(windows: [PinnedWindow] = []) {
        self.windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
    }

    public var count: Int {
        windowsByID.count
    }

    public var isEmpty: Bool {
        windowsByID.isEmpty
    }

    public var allWindows: [PinnedWindow] {
        Array(windowsByID.values)
    }

    public func window(id: UUID) -> PinnedWindow? {
        windowsByID[id]
    }

    @discardableResult
    public mutating func pin(
        reference: PinnedWindowReference,
        at pinnedAt: Date = .now
    ) -> PinnedWindow {
        if let existingID = matchingWindowID(for: reference),
           var existing = windowsByID[existingID] {
            existing.reference = reference
            existing.lastPinnedAt = pinnedAt
            existing.lastObservedAt = pinnedAt
            existing.invalidation = nil
            windowsByID[existingID] = existing
            return existing
        }

        let newWindow = PinnedWindow(
            reference: reference,
            lastPinnedAt: pinnedAt,
            lastObservedAt: pinnedAt
        )
        windowsByID[newWindow.id] = newWindow
        return newWindow
    }

    @discardableResult
    public mutating func markActivated(
        id: UUID,
        at activatedAt: Date = .now
    ) -> PinnedWindow? {
        guard var window = windowsByID[id] else {
            return nil
        }

        window.lastActivatedAt = activatedAt
        window.lastObservedAt = activatedAt
        windowsByID[id] = window
        return window
    }

    @discardableResult
    public mutating func markObserved(
        id: UUID,
        reference: PinnedWindowReference? = nil,
        at observedAt: Date = .now
    ) -> PinnedWindow? {
        guard var window = windowsByID[id] else {
            return nil
        }

        if let reference {
            window.reference = reference
        }

        window.lastObservedAt = observedAt
        windowsByID[id] = window
        return window
    }

    @discardableResult
    public mutating func markInvalidated(
        id: UUID,
        reason: PinnedWindowInvalidationReason,
        at invalidatedAt: Date = .now
    ) -> PinnedWindow? {
        guard var window = windowsByID[id] else {
            return nil
        }

        window.invalidation = PinnedWindowInvalidation(
            reason: reason,
            invalidatedAt: invalidatedAt
        )
        window.lastObservedAt = invalidatedAt
        windowsByID[id] = window
        return window
    }

    @discardableResult
    public mutating func unpin(id: UUID) -> PinnedWindow? {
        windowsByID.removeValue(forKey: id)
    }

    @discardableResult
    public mutating func unpinAll() -> [PinnedWindow] {
        let removed = allWindows
        windowsByID.removeAll()
        return removed
    }

    public func orderedWindows(mode: PinnedWindowOrderingMode) -> [PinnedWindow] {
        PinnedWindowOrdering.sort(allWindows, mode: mode)
    }

    private func matchingWindowID(for reference: PinnedWindowReference) -> UUID? {
        windowsByID.first { _, window in
            window.reference.likelyMatches(reference)
        }?.key
    }
}
