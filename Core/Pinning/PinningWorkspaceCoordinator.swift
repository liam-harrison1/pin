import Foundation
import DeskPinsAccessibility
import DeskPinsPinned
import DeskPinsWindowCatalog

public struct PinningWorkspaceCoordinator<
    CatalogReader: WindowCatalogReading,
    FocusReader: FocusedWindowReading
>: Sendable {
    private let catalogReader: CatalogReader
    private let focusedWindowReader: FocusReader
    private let reconciler: PinnedWindowCatalogReconciler

    public init(
        catalogReader: CatalogReader,
        focusedWindowReader: FocusReader,
        reconciler: PinnedWindowCatalogReconciler = .init()
    ) {
        self.catalogReader = catalogReader
        self.focusedWindowReader = focusedWindowReader
        self.reconciler = reconciler
    }

    public func captureFocus() -> PinningWorkspaceFocusCapture {
        do {
            let focusedWindow = try focusedWindowReader.currentFocusedWindow()
            return PinningWorkspaceFocusCapture(
                status: .available,
                focusedWindow: focusedWindow
            )
        } catch let error as FocusedWindowReadError {
            return PinningWorkspaceFocusCapture(
                status: mapFocusStatus(error),
                focusedWindow: nil
            )
        } catch {
            return PinningWorkspaceFocusCapture(
                status: .noFocusedWindow,
                focusedWindow: nil
            )
        }
    }

    public func refresh(
        store: inout PinnedWindowStore,
        filteringRules: WindowCatalogFilteringRules = .default,
        orderingMode: PinnedWindowOrderingMode = .recentInteractionFirst,
        focusCapture: PinningWorkspaceFocusCapture? = nil,
        at refreshedAt: Date = .now
    ) throws -> PinningWorkspaceSnapshot {
        let catalog = try catalogReader.currentWindowCatalog()
        let visibleEntries = catalog.filteredEntries(rules: filteringRules)
        let invalidatedPinnedWindows = reconciler.reconcile(
            store: &store,
            against: catalog,
            at: refreshedAt
        )
        let focusResolution = resolveFocus(
            store: store,
            visibleEntries: visibleEntries,
            capture: focusCapture ?? captureFocus()
        )

        return PinningWorkspaceSnapshot(
            catalog: catalog,
            visibleEntries: visibleEntries,
            focusedWindow: focusResolution.focusedWindow,
            focusedEntry: focusResolution.focusedEntry,
            focusedPinnedWindow: focusResolution.focusedPinnedWindow,
            focusStatus: focusResolution.status,
            invalidatedPinnedWindows: invalidatedPinnedWindows,
            pinnedWindows: store.orderedWindows(mode: orderingMode),
            refreshedAt: refreshedAt
        )
    }

    private func resolveFocus(
        store: PinnedWindowStore,
        visibleEntries: [WindowCatalogEntry],
        capture: PinningWorkspaceFocusCapture
    ) -> FocusResolution {
        guard let focusedWindow = capture.focusedWindow else {
            return FocusResolution(
                status: capture.status,
                focusedWindow: nil,
                focusedEntry: nil,
                focusedPinnedWindow: nil
            )
        }

        let focusedEntry = matchingCatalogEntry(
            for: focusedWindow,
            in: visibleEntries
        )
        let focusedPinnedWindow = store.matchingWindow(
            for: focusedWindow.asPinnedReference()
        )

        return FocusResolution(
            status: capture.status,
            focusedWindow: focusedWindow,
            focusedEntry: focusedEntry,
            focusedPinnedWindow: focusedPinnedWindow
        )
    }

    private func matchingCatalogEntry(
        for focusedWindow: FocusedWindowSnapshot,
        in visibleEntries: [WindowCatalogEntry]
    ) -> WindowCatalogEntry? {
        let reference = focusedWindow.asPinnedReference()
        return visibleEntries.first { entry in
            entry.asPinnedReference().likelyMatches(reference)
        }
    }

    private func mapFocusStatus(
        _ error: FocusedWindowReadError
    ) -> PinningWorkspaceFocusStatus {
        switch error {
        case .accessibilityNotTrusted:
            return .requiresAccessibilityPermission
        case .noFocusedWindow, .noFrontmostApplication:
            return .noFocusedWindow
        case .unsupportedValue, .axError:
            return .noFocusedWindow
        }
    }
}

private struct FocusResolution {
    let status: PinningWorkspaceFocusStatus
    let focusedWindow: FocusedWindowSnapshot?
    let focusedEntry: WindowCatalogEntry?
    let focusedPinnedWindow: PinnedWindow?
}
