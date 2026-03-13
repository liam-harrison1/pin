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
        let catalogReferences = catalog.entries.map { $0.asPinnedReference() }
        var invalidated: [PinnedWindow] = []

        for window in store.allWindows {
            let stillPresent = catalogReferences.contains { reference in
                window.reference.likelyMatches(reference)
            }

            guard !stillPresent else {
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
