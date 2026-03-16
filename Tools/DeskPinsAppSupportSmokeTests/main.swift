import Foundation
import DeskPinsAccessibility
import DeskPinsAppSupport
import DeskPinsOverlay
import DeskPinsPinned
import DeskPinsPinning
import DeskPinsWindowCatalog

// swiftlint:disable type_body_length
@main
struct DeskPinsAppSupportSmokeTests {
    @MainActor
    static func main() {
        do {
            try testControllerLoadsPersistedStoreAndRefreshesWorkspace()
            try testControllerMenuCapturePreservesFocusForToggle()
            try testControllerCanUnpinPersistedWindowByID()
            try testControllerCanToggleVisibleWindowFromWorkspace()
            try testControllerCanBringPinnedWindowForward()
            try testControllerCreatesOverlayTargetsForVisiblePinnedWindows()
            try testControllerAppliesOverlayLeaseRenderPolicies()
            try testOverlayLeaseStateTransitions()
            try testControllerPromotesFrontmostPinnedWindowOnRefresh()
            print("DeskPinsAppSupport smoke tests passed")
        } catch {
            fputs("App support smoke test failure: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func testControllerLoadsPersistedStoreAndRefreshesWorkspace() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let savedStore = PinnedWindowStore(
            windows: [
                PinnedWindow(
                    reference: PinnedWindowReference(
                        ownerPID: 801,
                        windowTitle: "Persisted Window",
                        windowNumber: 1001
                    ),
                    lastPinnedAt: Date(timeIntervalSince1970: 13_000)
                )
            ]
        )
        _ = try persistence.saveStore(
            savedStore,
            savedAt: Date(timeIntervalSince1970: 13_100)
        )

        let controller = try DeskPinsMenuBarStateController(
            trustChecker: StaticAccessibilityTrustChecker(status: .trusted),
            focusedReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 801,
                    applicationName: "Notes",
                    windowTitle: "Persisted Window"
                )
            ),
            catalogReader: StaticWindowCatalogReader(
                catalog: WindowCatalog(
                    entries: [
                        WindowCatalogEntry(
                            frontToBackIndex: 0,
                            ownerPID: 801,
                            ownerName: "Notes",
                            windowTitle: "Persisted Window",
                            windowNumber: 1001,
                            layer: 0,
                            alpha: 1,
                            bounds: WindowCatalogBounds(
                                x: 0,
                                y: 0,
                                width: 400,
                                height: 300
                            ),
                            isOnScreen: true
                        )
                    ]
                )
            ),
            persistence: persistence
        )

        let snapshot = try controller.refreshWorkspace()
        let presentation = controller.presentation()

        try expect(
            snapshot.focusedPinnedWindow?.windowNumber == 1001,
            message: "refresh should reconnect the focused window to the persisted pinned store"
        )
        try expect(
            presentation.pinnedCount == 1,
            message: "presentation should surface the persisted pinned window count"
        )
        try expect(
            presentation.focusedWindowTitle == "Persisted Window",
            message: "presentation should surface the focused window title after refresh"
        )
        try expect(
            presentation.visibleWindows.map(\.title) == ["Persisted Window"],
            message: "presentation should surface visible window items from the latest workspace snapshot"
        )
    }

    @MainActor
    private static func testControllerMenuCapturePreservesFocusForToggle() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let controller = try DeskPinsMenuBarStateController(
            trustChecker: StaticAccessibilityTrustChecker(status: .trusted),
            focusedReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 802,
                    applicationName: "Safari",
                    windowTitle: "Spec"
                )
            ),
            catalogReader: StaticWindowCatalogReader(
                catalog: WindowCatalog(entries: [])
            ),
            persistence: persistence
        )

        _ = try controller.captureWorkspaceForMenu()
        let outcome = try controller.togglePresentedFocusedWindow()
        let reloadedStore = try persistence.loadStore()

        switch outcome {
        case .pinned(let window):
            try expect(
                window.windowTitle == "Spec",
                message: "menu toggle should pin the last captured focused window"
            )
        case .unpinned, .requiresAccessibilityPermission, .noFocusedWindow:
            throw SmokeTestFailure(
                message: "menu toggle should pin the focused window in the happy path"
            )
        }

        try expect(
            reloadedStore.count == 1,
            message: "menu toggle should persist the updated pinned-window store"
        )
        try expect(
            controller.presentation().pinnedWindows.map(\.title) == ["Spec"],
            message: "presentation should surface the newly pinned window title"
        )
    }

    @MainActor
    private static func testControllerCanUnpinPersistedWindowByID() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let pinnedWindow = PinnedWindow(
            reference: PinnedWindowReference(
                ownerPID: 803,
                windowTitle: "Pinned Tab",
                windowNumber: 1003
            ),
            lastPinnedAt: Date(timeIntervalSince1970: 14_000)
        )
        _ = try persistence.saveStore(
            PinnedWindowStore(windows: [pinnedWindow]),
            savedAt: Date(timeIntervalSince1970: 14_100)
        )

        let controller = try DeskPinsMenuBarStateController(
            trustChecker: StaticAccessibilityTrustChecker(status: .trusted),
            focusedReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 900,
                    applicationName: "Other App",
                    windowTitle: "Unrelated"
                )
            ),
            catalogReader: StaticWindowCatalogReader(catalog: WindowCatalog(entries: [])),
            persistence: persistence
        )

        let removed = try controller.unpinWindow(id: pinnedWindow.id)
        let reloadedStore = try persistence.loadStore()

        try expect(
            removed?.id == pinnedWindow.id,
            message: "app controller should be able to unpin a persisted window by identifier"
        )
        try expect(
            reloadedStore.isEmpty,
            message: "unpinning from the menu should persist the updated empty store"
        )
    }

    @MainActor
    private static func testControllerCanToggleVisibleWindowFromWorkspace() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let visibleEntry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 804,
            ownerName: "Mail",
            windowTitle: "Inbox",
            windowNumber: 1004,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 0, y: 0, width: 500, height: 350),
            isOnScreen: true
        )
        let controller = try DeskPinsMenuBarStateController(
            trustChecker: StaticAccessibilityTrustChecker(status: .trusted),
            focusedReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 999,
                    applicationName: "Other App",
                    windowTitle: "Other"
                )
            ),
            catalogReader: StaticWindowCatalogReader(
                catalog: WindowCatalog(entries: [visibleEntry])
            ),
            persistence: persistence
        )

        _ = try controller.refreshWorkspace()
        let firstResult = try controller.toggleVisibleWindow(id: visibleEntry.id)
        let secondResult = try controller.toggleVisibleWindow(id: visibleEntry.id)

        switch firstResult {
        case .pinned(let window):
            try expect(
                window.windowTitle == "Inbox",
                message: "visible-window toggle should pin the selected catalog entry"
            )
        case .unpinned, .none:
            throw SmokeTestFailure(
                message: "visible-window toggle should pin on the first invocation"
            )
        }

        switch secondResult {
        case .unpinned(let window):
            try expect(
                window.windowTitle == "Inbox",
                message: "visible-window toggle should unpin the selected catalog entry on the second invocation"
            )
        case .pinned, .none:
            throw SmokeTestFailure(
                message: "visible-window toggle should unpin on the second invocation"
            )
        }

        let reloadedStore = try persistence.loadStore()
        try expect(
            reloadedStore.isEmpty,
            message: "visible-window toggle should keep persistence in sync with the menu action"
        )
    }

    @MainActor
    private static func testControllerCreatesOverlayTargetsForVisiblePinnedWindows() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let pinnedWindow = PinnedWindow(
            reference: PinnedWindowReference(
                ownerPID: 805,
                windowTitle: "Reference",
                windowNumber: 1005,
                bounds: PinnedWindowBounds(x: 40, y: 50, width: 600, height: 400)
            ),
            lastPinnedAt: Date(timeIntervalSince1970: 15_000)
        )
        _ = try persistence.saveStore(
            PinnedWindowStore(windows: [pinnedWindow]),
            savedAt: Date(timeIntervalSince1970: 15_100)
        )

        let visibleEntry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 805,
            ownerName: "Notes",
            windowTitle: "Reference",
            windowNumber: 1005,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 60, y: 70, width: 620, height: 420),
            isOnScreen: true
        )
        let controller = try DeskPinsMenuBarStateController(
            trustChecker: StaticAccessibilityTrustChecker(status: .trusted),
            focusedReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 805,
                    applicationName: "Notes",
                    windowTitle: "Reference"
                )
            ),
            catalogReader: StaticWindowCatalogReader(
                catalog: WindowCatalog(entries: [visibleEntry])
            ),
            persistence: persistence
        )

        _ = try controller.refreshWorkspace()
        let overlays = controller.overlayTargets()

        try expect(
            overlays.count == 1,
            message: "app controller should create one overlay target for a visible pinned window"
        )
        try expect(
            overlays.first?.frame == CGRect(x: 60, y: 70, width: 620, height: 420),
            message: "overlay targets should prefer the latest visible window bounds"
        )
    }

    @MainActor
    private static func testControllerCanBringPinnedWindowForward() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let pinnedWindow = PinnedWindow(
            reference: PinnedWindowReference(
                ownerPID: 806,
                windowTitle: "Project Plan",
                windowNumber: 1006,
                bounds: PinnedWindowBounds(x: 80, y: 90, width: 640, height: 440)
            ),
            lastPinnedAt: Date(timeIntervalSince1970: 16_000)
        )
        _ = try persistence.saveStore(
            PinnedWindowStore(windows: [pinnedWindow]),
            savedAt: Date(timeIntervalSince1970: 16_100)
        )

        let windowActivator = RecordingWindowActivator()
        let controller = try DeskPinsMenuBarStateController(
            trustChecker: StaticAccessibilityTrustChecker(status: .trusted),
            focusedReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 806,
                    applicationName: "Notes",
                    windowTitle: "Project Plan"
                )
            ),
            catalogReader: StaticWindowCatalogReader(catalog: WindowCatalog(entries: [])),
            persistence: persistence,
            windowActivator: windowActivator
        )

        let activated = try controller.activatePinnedWindow(id: pinnedWindow.id)

        try expect(
            activated?.id == pinnedWindow.id,
            message: "activating a pinned window should return the matching pinned window"
        )
        try expect(
            windowActivator.activatedReferences == [pinnedWindow.reference],
            message: "app controller should route bring-forward requests through the window activator"
        )
    }

    @MainActor
    private static func testControllerAppliesOverlayLeaseRenderPolicies() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let ownerWindow = PinnedWindow(
            reference: PinnedWindowReference(
                ownerPID: 861,
                windowTitle: "Owner Window",
                windowNumber: 1861,
                bounds: PinnedWindowBounds(x: 80, y: 80, width: 540, height: 360)
            ),
            lastPinnedAt: Date(timeIntervalSince1970: 16_100)
        )
        let suppressedWindow = PinnedWindow(
            reference: PinnedWindowReference(
                ownerPID: 862,
                windowTitle: "Suppressed Window",
                windowNumber: 1862,
                bounds: PinnedWindowBounds(x: 120, y: 120, width: 520, height: 340)
            ),
            lastPinnedAt: Date(timeIntervalSince1970: 16_110)
        )
        _ = try persistence.saveStore(
            PinnedWindowStore(windows: [ownerWindow, suppressedWindow]),
            savedAt: Date(timeIntervalSince1970: 16_200)
        )

        let visibleEntries = [
            WindowCatalogEntry(
                frontToBackIndex: 0,
                ownerPID: 861,
                ownerName: "AppA",
                windowTitle: "Owner Window",
                windowNumber: 1861,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 80, y: 80, width: 540, height: 360),
                isOnScreen: true
            ),
            WindowCatalogEntry(
                frontToBackIndex: 1,
                ownerPID: 862,
                ownerName: "AppB",
                windowTitle: "Suppressed Window",
                windowNumber: 1862,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 120, y: 120, width: 520, height: 340),
                isOnScreen: true
            )
        ]
        let controller = try DeskPinsMenuBarStateController(
            trustChecker: StaticAccessibilityTrustChecker(status: .trusted),
            focusedReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 861,
                    applicationName: "AppA",
                    windowTitle: "Owner Window"
                )
            ),
            catalogReader: StaticWindowCatalogReader(catalog: WindowCatalog(entries: visibleEntries)),
            persistence: persistence
        )

        _ = try controller.refreshWorkspace()
        controller.setOverlayInteractionLease(
            ownerID: ownerWindow.id,
            active: true,
            suppressedWindowIDs: [suppressedWindow.id]
        )
        let leasedTargets = controller.overlayTargets()

        let ownerPolicy = leasedTargets.first(where: { $0.id == ownerWindow.id })?.renderPolicy
        let suppressedPolicy = leasedTargets.first(where: { $0.id == suppressedWindow.id })?.renderPolicy
        try expect(
            ownerPolicy == .directInteractionOwner,
            message: "active lease owner should render in direct-interaction mode"
        )
        try expect(
            suppressedPolicy == .suppressed,
            message: "suppressed lease competitors should render in suppressed mode"
        )

        controller.clearOverlayInteractionLease()
        let resetTargets = controller.overlayTargets()
        let resetPolicies = resetTargets.map(\.renderPolicy)
        try expect(
            resetPolicies.allSatisfy { $0 == .mirrorVisible },
            message: "clearing lease should restore mirror rendering for all pinned targets"
        )
    }

    private static func testOverlayLeaseStateTransitions() throws {
        let ownerID = UUID()
        let competitorID = UUID()
        var leaseState = OverlayInteractionLeaseState()

        leaseState.enterAcquiring(
            ownerID: ownerID,
            suppressedWindowIDs: [competitorID],
            at: Date(timeIntervalSince1970: 500)
        )
        try expect(
            leaseState.mode == .acquiring(ownerID: ownerID),
            message: "lease state should enter acquiring mode for the requested owner"
        )
        try expect(
            leaseState.suppressedWindowIDs == [competitorID],
            message: "lease state should preserve suppressed competitor ids while acquiring"
        )

        try expect(
            leaseState.activate(ownerID: UUID()) == false,
            message: "lease state activation should reject a mismatched owner id"
        )
        try expect(
            leaseState.activate(ownerID: ownerID),
            message: "lease state activation should succeed for the acquiring owner id"
        )
        try expect(
            leaseState.mode == .active(ownerID: ownerID),
            message: "lease state should transition to active mode after activation"
        )

        leaseState.markFocusUnknownIfNeeded(at: Date(timeIntervalSince1970: 501))
        try expect(
            leaseState.unknownFocusWithinGracePeriod(
                at: Date(timeIntervalSince1970: 501.05),
                graceInterval: 0.12
            ),
            message: "lease state should honor focus-unknown grace interval after activation"
        )

        leaseState.clear()
        try expect(
            leaseState.mode == .none,
            message: "clearing lease state should return it to none mode"
        )
        try expect(
            leaseState.suppressedWindowIDs.isEmpty,
            message: "clearing lease state should remove suppressed competitor ids"
        )
        try expect(
            leaseState.handshakeElapsedMilliseconds() == nil,
            message: "clearing lease state should drop handshake timing context"
        )
    }

    @MainActor
    private static func testControllerPromotesFrontmostPinnedWindowOnRefresh() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let olderPin = PinnedWindow(
            reference: PinnedWindowReference(
                ownerPID: 910,
                windowTitle: "Older Pin",
                windowNumber: 1910,
                bounds: PinnedWindowBounds(x: 10, y: 10, width: 600, height: 380)
            ),
            lastPinnedAt: Date(timeIntervalSince1970: 17_000)
        )
        let newerPin = PinnedWindow(
            reference: PinnedWindowReference(
                ownerPID: 920,
                windowTitle: "Newer Pin",
                windowNumber: 1920,
                bounds: PinnedWindowBounds(x: 40, y: 40, width: 640, height: 420)
            ),
            lastPinnedAt: Date(timeIntervalSince1970: 17_100)
        )
        _ = try persistence.saveStore(
            PinnedWindowStore(windows: [olderPin, newerPin]),
            savedAt: Date(timeIntervalSince1970: 17_200)
        )

        let frontmostOlderEntry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 910,
            ownerName: "Notes",
            windowTitle: "Older Pin",
            windowNumber: 1910,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 12, y: 14, width: 602, height: 382),
            isOnScreen: true
        )
        let secondNewerEntry = WindowCatalogEntry(
            frontToBackIndex: 1,
            ownerPID: 920,
            ownerName: "Browser",
            windowTitle: "Newer Pin",
            windowNumber: 1920,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 42, y: 44, width: 642, height: 422),
            isOnScreen: true
        )

        let controller = try DeskPinsMenuBarStateController(
            trustChecker: StaticAccessibilityTrustChecker(status: .trusted),
            focusedReader: StaticFocusedWindowReader(
                snapshot: FocusedWindowSnapshot(
                    ownerPID: 910,
                    applicationName: "Notes",
                    windowTitle: "Older Pin"
                )
            ),
            catalogReader: StaticWindowCatalogReader(
                catalog: WindowCatalog(entries: [frontmostOlderEntry, secondNewerEntry])
            ),
            persistence: persistence
        )

        _ = try controller.refreshWorkspace()

        try expect(
            controller.presentation().pinnedWindows.map(\.title) == ["Older Pin", "Newer Pin"],
            message: "refresh should promote the frontmost pinned window so click order drives pin stacking"
        )
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskPinsAppSupport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempURL,
            withIntermediateDirectories: true
        )
        return tempURL
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        message: String
    ) throws {
        if condition() {
            return
        }

        throw SmokeTestFailure(message: message)
    }
}
// swiftlint:enable type_body_length

private struct SmokeTestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

private final class RecordingWindowActivator: WindowActivating, @unchecked Sendable {
    private(set) var activatedReferences: [PinnedWindowReference] = []

    func activateWindow(reference: PinnedWindowReference) throws {
        activatedReferences.append(reference)
    }
}
