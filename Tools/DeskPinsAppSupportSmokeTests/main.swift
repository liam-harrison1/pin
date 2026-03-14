import Foundation
import DeskPinsAccessibility
import DeskPinsAppSupport
import DeskPinsOverlay
import DeskPinsPinned
import DeskPinsPinning
import DeskPinsWindowCatalog

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
