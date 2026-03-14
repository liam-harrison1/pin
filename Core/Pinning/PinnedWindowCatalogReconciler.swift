import Foundation
import DeskPinsPinned
import DeskPinsWindowCatalog

public struct PinnedWindowCatalogReconciler: Sendable {
    public init() {}

    @discardableResult
    public func reconcile(
        store: inout PinnedWindowStore,
        against catalog: WindowCatalog,
        at date: Date = .now
    ) -> [PinnedWindow] {
        var invalidated: [PinnedWindow] = []

        for window in store.allWindows {
            if let matchingEntry = catalog.entries.first(where: { entry in
                window.reference.likelyMatches(entry.asPinnedReference())
            }) {
                _ = store.markObserved(
                    id: window.id,
                    reference: matchingEntry.asPinnedReference(),
                    at: date
                )
                continue
            }

            if let updated = store.markInvalidated(
                id: window.id,
                reason: .noLongerMatched,
                at: date
            ) {
                invalidated.append(updated)
            }
        }

        return invalidated
    }
}
