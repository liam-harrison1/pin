import Foundation
import DeskPinsAccessibility
import DeskPinsPinning
import DeskPinsPinned
import DeskPinsWindowCatalog

@main
struct DeskPinsPinningSmokeTests {
    static func main() {
        do {
            try testPinCurrentWindowCreatesPinnedEntry()
            try testToggleCurrentWindowUnpinsMatchingEntry()
            try testUnpinCurrentWindowReturnsNilWhenNotPinned()
            try testPinCatalogEntryCreatesPinnedEntry()
            try testToggleCatalogEntryUnpinsMatchingEntry()
            try testAttemptPinMapsMissingPermissionToRecoverableOutcome()
            try testAttemptToggleMapsMissingFocusedWindowToRecoverableOutcome()
            try testReconcileInvalidatesPinnedWindowsMissingFromCatalog()
            try testWorkspaceRefreshBuildsFocusedSnapshotAndPinnedMatch()
            try testWorkspaceRefreshMapsMissingPermissionWithoutDroppingCatalog()
            print("DeskPinsPinning smoke tests passed")
        } catch {
            fputs("Pinning smoke test failure: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func testPinCurrentWindowCreatesPinnedEntry() throws {
        let snapshot = FocusedWindowSnapshot(
            ownerPID: 101,
            applicationName: "Notes",
            windowTitle: "Plan"
        )
        let service = PinCurrentWindowService(reader: StaticFocusedWindowReader(snapshot: snapshot))
        var store = PinnedWindowStore()

        let pinned = try service.pinCurrentWindow(in: &store, at: Date(timeIntervalSince1970: 7_000))

        try expect(store.count == 1, message: "pin current window should add one pinned entry")
        try expect(pinned.windowTitle == "Plan", message: "pin current window should preserve the focused window title")
    }

    private static func testToggleCurrentWindowUnpinsMatchingEntry() throws {
        let snapshot = FocusedWindowSnapshot(
            ownerPID: 102,
            applicationName: "Terminal",
            windowTitle: "Logs"
        )
        let service = PinCurrentWindowService(reader: StaticFocusedWindowReader(snapshot: snapshot))
        var store = PinnedWindowStore()

        _ = try service.pinCurrentWindow(in: &store, at: Date(timeIntervalSince1970: 8_000))
        let result = try service.toggleCurrentWindow(in: &store, at: Date(timeIntervalSince1970: 8_100))

        switch result {
        case .unpinned(let window):
            try expect(
                window.windowTitle == "Logs",
                message: "toggle should return the unpinned current window when it was already pinned"
            )
            try expect(
                store.isEmpty,
                message: "toggle should remove the current window when it was already pinned"
            )
        case .pinned:
            throw SmokeTestFailure(message: "toggle should unpin an already pinned current window")
        }
    }

    private static func testUnpinCurrentWindowReturnsNilWhenNotPinned() throws {
        let snapshot = FocusedWindowSnapshot(
            ownerPID: 103,
            applicationName: "Browser",
            windowTitle: "Docs"
        )
        let service = PinCurrentWindowService(reader: StaticFocusedWindowReader(snapshot: snapshot))
        var store = PinnedWindowStore()

        let removed = try service.unpinCurrentWindow(from: &store)
        try expect(removed == nil, message: "unpin current window should return nil when no matching pinned entry exists")
    }

    private static func testPinCatalogEntryCreatesPinnedEntry() throws {
        let entry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 201,
            ownerName: "Notes",
            windowTitle: "Roadmap",
            windowNumber: 401,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 10, y: 20, width: 300, height: 200),
            isOnScreen: true
        )
        let service = PinCatalogWindowService()
        var store = PinnedWindowStore()

        let pinned = service.pin(entry: entry, in: &store, at: Date(timeIntervalSince1970: 9_000))

        try expect(store.count == 1, message: "pin catalog entry should add one pinned entry")
        try expect(pinned.windowNumber == 401, message: "pin catalog entry should preserve the source window number")
        try expect(pinned.windowTitle == "Roadmap", message: "pin catalog entry should preserve the source title")
    }

    private static func testToggleCatalogEntryUnpinsMatchingEntry() throws {
        let entry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 202,
            ownerName: "Safari",
            windowTitle: "Spec",
            windowNumber: 402,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true
        )
        let service = PinCatalogWindowService()
        var store = PinnedWindowStore()

        _ = service.pin(entry: entry, in: &store, at: Date(timeIntervalSince1970: 9_100))
        let result = service.toggle(entry: entry, in: &store, at: Date(timeIntervalSince1970: 9_200))

        switch result {
        case .unpinned(let window):
            try expect(window.windowNumber == 402, message: "toggle should return the matching catalog-backed pinned window when unpinning")
            try expect(store.isEmpty, message: "toggle should remove the catalog-backed window when it was already pinned")
        case .pinned:
            throw SmokeTestFailure(message: "toggle should unpin an already pinned catalog entry")
        }
    }

    private static func testAttemptPinMapsMissingPermissionToRecoverableOutcome() throws {
        let service = PinCurrentWindowService(reader: ThrowingFocusedWindowReader(error: .accessibilityNotTrusted))
        var store = PinnedWindowStore()

        let outcome = service.attemptPinCurrentWindow(in: &store, at: Date(timeIntervalSince1970: 9_300))
        try expect(
            outcome == .requiresAccessibilityPermission,
            message: "attemptPin should surface missing accessibility permission as a recoverable outcome"
        )
        try expect(
            store.isEmpty,
            message: "attemptPin should not mutate the store when permission is missing"
        )
    }

    private static func testAttemptToggleMapsMissingFocusedWindowToRecoverableOutcome() throws {
        let service = PinCurrentWindowService(reader: ThrowingFocusedWindowReader(error: .noFocusedWindow))
        var store = PinnedWindowStore()

        let outcome = service.attemptToggleCurrentWindow(in: &store, at: Date(timeIntervalSince1970: 9_400))
        try expect(
            outcome == .noFocusedWindow,
            message: "attemptToggle should surface a missing focused window as a recoverable outcome"
        )
        try expect(
            store.isEmpty,
            message: "attemptToggle should leave the store unchanged when no focused window is available"
        )
    }

    private static func testReconcileInvalidatesPinnedWindowsMissingFromCatalog() throws {
        let entry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 301,
            ownerName: "Notes",
            windowTitle: "Still Here",
            windowNumber: 601,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 0, y: 0, width: 400, height: 300),
            isOnScreen: true
        )
        let service = PinCatalogWindowService()
        let reconciler = PinnedWindowCatalogReconciler()
        var store = PinnedWindowStore()

        _ = service.pin(entry: entry, in: &store, at: Date(timeIntervalSince1970: 9_500))
        _ = store.pin(
            reference: PinnedWindowReference(
                ownerPID: 302,
                windowTitle: "Gone",
                windowNumber: 602
            ),
            at: Date(timeIntervalSince1970: 9_510)
        )

        let invalidated = reconciler.reconcile(
            store: &store,
            against: WindowCatalog(entries: [entry]),
            at: Date(timeIntervalSince1970: 9_600)
        )

        try expect(
            invalidated.count == 1,
            message: "reconcile should invalidate pinned windows missing from the refreshed catalog"
        )
        try expect(
            invalidated.first?.windowTitle == "Gone",
            message: "reconcile should invalidate the missing pinned window"
        )
        let invalidatedReason = store
            .orderedWindows(mode: .recentPinFirst)
            .first(where: { $0.windowTitle == "Gone" })?
            .invalidation?.reason
        try expect(
            invalidatedReason == .noLongerMatched,
            message: "reconcile should record the noLongerMatched invalidation reason"
        )
    }

    private static func testWorkspaceRefreshBuildsFocusedSnapshotAndPinnedMatch() throws {
        let focusedEntry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 401,
            ownerName: "Notes",
            windowTitle: "Sprint Plan",
            windowNumber: 701,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 12, y: 24, width: 500, height: 320),
            isOnScreen: true
        )
        let backgroundEntry = WindowCatalogEntry(
            frontToBackIndex: 1,
            ownerPID: 402,
            ownerName: "Terminal",
            windowTitle: "Logs",
            windowNumber: 702,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 80, y: 120, width: 640, height: 480),
            isOnScreen: true
        )
        let coordinator = PinningWorkspaceCoordinator(
            catalogReader: StaticWindowCatalogReader(
                catalog: WindowCatalog(entries: [focusedEntry, backgroundEntry])
            ),
            focusedWindowReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 401,
                    applicationName: "Notes",
                    windowTitle: "Sprint Plan",
                    bounds: focusedEntry.asPinnedReference().bounds
                )
            )
        )
        var store = PinnedWindowStore(
            windows: [
                PinnedWindow(
                    reference: focusedEntry.asPinnedReference(),
                    lastPinnedAt: Date(timeIntervalSince1970: 10_000)
                )
            ]
        )

        let snapshot = try coordinator.refresh(
            store: &store,
            at: Date(timeIntervalSince1970: 10_100)
        )

        try expect(
            snapshot.focusStatus == .available,
            message: "workspace refresh should report an available focus state when the focused window is readable"
        )
        try expect(
            snapshot.visibleEntries.count == 2,
            message: "workspace refresh should retain the filtered catalog entries"
        )
        try expect(
            snapshot.focusedEntry?.windowNumber == 701,
            message: "workspace refresh should match the focused window back to the visible catalog entry"
        )
        try expect(
            snapshot.focusedPinnedWindow?.windowNumber == 701,
            message: "workspace refresh should surface the pinned window that matches the focused snapshot"
        )
        try expect(
            snapshot.invalidatedPinnedWindows.isEmpty,
            message: "workspace refresh should not invalidate pinned windows that are still present in the catalog"
        )
    }

    private static func testWorkspaceRefreshMapsMissingPermissionWithoutDroppingCatalog() throws {
        let visibleEntry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 501,
            ownerName: "Safari",
            windowTitle: "DeskPins Spec",
            windowNumber: 801,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 0, y: 0, width: 900, height: 700),
            isOnScreen: true
        )
        let missingEntryReference = PinnedWindowReference(
            ownerPID: 999,
            windowTitle: "Missing",
            windowNumber: 899
        )
        let coordinator = PinningWorkspaceCoordinator(
            catalogReader: StaticWindowCatalogReader(
                catalog: WindowCatalog(entries: [visibleEntry])
            ),
            focusedWindowReader: ThrowingFocusedWindowReader(error: .accessibilityNotTrusted)
        )
        var store = PinnedWindowStore(
            windows: [
                PinnedWindow(
                    reference: missingEntryReference,
                    lastPinnedAt: Date(timeIntervalSince1970: 10_200)
                )
            ]
        )

        let snapshot = try coordinator.refresh(
            store: &store,
            at: Date(timeIntervalSince1970: 10_300)
        )

        try expect(
            snapshot.focusStatus == .requiresAccessibilityPermission,
            message: "workspace refresh should surface missing accessibility permission as a recoverable focus state"
        )
        try expect(
            snapshot.focusedWindow == nil,
            message: "workspace refresh should not return a focused snapshot when permission is missing"
        )
        try expect(
            snapshot.visibleEntries.count == 1,
            message: "workspace refresh should still return the catalog when focused-window access is unavailable"
        )
        try expect(
            snapshot.invalidatedPinnedWindows.count == 1,
            message: "workspace refresh should still reconcile pinned windows against the current catalog"
        )
        try expect(
            snapshot.invalidatedPinnedWindows.first?.invalidation?.reason == .noLongerMatched,
            message: "workspace refresh should carry through stale-window invalidation results"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, message: String) throws {
        if condition() {
            return
        }

        throw SmokeTestFailure(message: message)
    }
}

private struct SmokeTestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

private struct ThrowingFocusedWindowReader: FocusedWindowReading {
    let error: FocusedWindowReadError

    func currentFocusedWindow() throws -> FocusedWindowSnapshot {
        throw error
    }
}
