import Foundation

public enum OverlayInteractionLeaseMode: Sendable, Equatable {
    case none
    case acquiring(ownerID: UUID)
    case active(ownerID: UUID)

    public var ownerID: UUID? {
        switch self {
        case .none:
            return nil
        case .acquiring(let ownerID), .active(let ownerID):
            return ownerID
        }
    }

    public var label: String {
        switch self {
        case .none:
            return "none"
        case .acquiring:
            return "acquiring"
        case .active:
            return "active"
        }
    }
}

public struct OverlayInteractionLeaseState: Sendable, Equatable {
    public private(set) var mode: OverlayInteractionLeaseMode
    public private(set) var suppressedWindowIDs: Set<UUID>
    public private(set) var focusUnknownSince: Date?
    public private(set) var handshakeStartedAt: Date?

    public init(
        mode: OverlayInteractionLeaseMode = .none,
        suppressedWindowIDs: Set<UUID> = [],
        focusUnknownSince: Date? = nil,
        handshakeStartedAt: Date? = nil
    ) {
        self.mode = mode
        self.suppressedWindowIDs = suppressedWindowIDs
        self.focusUnknownSince = focusUnknownSince
        self.handshakeStartedAt = handshakeStartedAt
    }

    public mutating func enterAcquiring(
        ownerID: UUID,
        suppressedWindowIDs: Set<UUID>,
        at date: Date = .now
    ) {
        mode = .acquiring(ownerID: ownerID)
        self.suppressedWindowIDs = suppressedWindowIDs
        focusUnknownSince = nil
        handshakeStartedAt = date
    }

    @discardableResult
    public mutating func activate(ownerID: UUID) -> Bool {
        guard case .acquiring(let currentOwnerID) = mode,
              currentOwnerID == ownerID else {
            return false
        }

        mode = .active(ownerID: ownerID)
        focusUnknownSince = nil
        return true
    }

    public mutating func clear() {
        mode = .none
        suppressedWindowIDs.removeAll()
        focusUnknownSince = nil
        handshakeStartedAt = nil
    }

    public mutating func ensureHandshakeStarted(at date: Date = .now) {
        guard handshakeStartedAt == nil else {
            return
        }

        handshakeStartedAt = date
    }

    public mutating func markFocusUnknownIfNeeded(at date: Date = .now) {
        guard focusUnknownSince == nil else {
            return
        }

        focusUnknownSince = date
    }

    public mutating func clearFocusUnknown() {
        focusUnknownSince = nil
    }

    public func unknownFocusWithinGracePeriod(
        at now: Date = .now,
        graceInterval: TimeInterval
    ) -> Bool {
        guard let focusUnknownSince else {
            return false
        }

        return now.timeIntervalSince(focusUnknownSince) < graceInterval
    }

    public func handshakeElapsedMilliseconds(at now: Date = .now) -> Int? {
        guard let handshakeStartedAt else {
            return nil
        }

        return Int(now.timeIntervalSince(handshakeStartedAt) * 1_000)
    }
}
