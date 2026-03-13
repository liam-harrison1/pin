import Foundation
import DeskPinsPinned
import DeskPinsWindowCatalog

public enum PinCatalogWindowToggleResult: Sendable, Equatable {
    case pinned(PinnedWindow)
    case unpinned(PinnedWindow)
}

public struct PinCatalogWindowService: Sendable {
    public init() {}

    public func pin(
        entry: WindowCatalogEntry,
        in store: inout PinnedWindowStore,
        at pinnedAt: Date = .now
    ) -> PinnedWindow {
        store.pin(reference: entry.asPinnedReference(), at: pinnedAt)
    }

    public func unpin(
        entry: WindowCatalogEntry,
        from store: inout PinnedWindowStore
    ) -> PinnedWindow? {
        store.unpin(reference: entry.asPinnedReference())
    }

    public func toggle(
        entry: WindowCatalogEntry,
        in store: inout PinnedWindowStore,
        at date: Date = .now
    ) -> PinCatalogWindowToggleResult {
        if let unpinned = store.unpin(reference: entry.asPinnedReference()) {
            return .unpinned(unpinned)
        }

        let pinned = store.pin(reference: entry.asPinnedReference(), at: date)
        return .pinned(pinned)
    }
}
