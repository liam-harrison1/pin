import Foundation
import DeskPinsAccessibility
import DeskPinsPinned

public enum PinCurrentWindowToggleResult: Sendable, Equatable {
    case pinned(PinnedWindow)
    case unpinned(PinnedWindow)
}

public struct PinCurrentWindowService<Reader: FocusedWindowReading>: Sendable {
    private let reader: Reader

    public init(reader: Reader) {
        self.reader = reader
    }

    public func pinCurrentWindow(
        in store: inout PinnedWindowStore,
        at pinnedAt: Date = .now
    ) throws -> PinnedWindow {
        let snapshot = try reader.currentFocusedWindow()
        return store.pin(reference: snapshot.asPinnedReference(), at: pinnedAt)
    }

    public func unpinCurrentWindow(
        from store: inout PinnedWindowStore
    ) throws -> PinnedWindow? {
        let snapshot = try reader.currentFocusedWindow()
        return store.unpin(reference: snapshot.asPinnedReference())
    }

    public func toggleCurrentWindow(
        in store: inout PinnedWindowStore,
        at date: Date = .now
    ) throws -> PinCurrentWindowToggleResult {
        let snapshot = try reader.currentFocusedWindow()
        let reference = snapshot.asPinnedReference()

        if let unpinned = store.unpin(reference: reference) {
            return .unpinned(unpinned)
        }

        let pinned = store.pin(reference: reference, at: date)
        return .pinned(pinned)
    }
}
