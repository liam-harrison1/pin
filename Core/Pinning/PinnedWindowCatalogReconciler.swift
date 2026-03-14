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
                let updatedReference = matchingEntry.asPinnedReference()
                let shouldRefreshObservedState =
                    window.isInvalidated || window.reference != updatedReference

                if shouldRefreshObservedState {
                    _ = store.markObserved(
                        id: window.id,
                        reference: updatedReference,
                        at: date
                    )
                }
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
