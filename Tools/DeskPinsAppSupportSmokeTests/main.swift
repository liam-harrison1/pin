import Foundation
import DeskPinsAccessibility
import DeskPinsAppSupport
import DeskPinsPinned
import DeskPinsPinning
import DeskPinsWindowCatalog

@main
struct DeskPinsAppSupportSmokeTests {
    @MainActor
    static func main() {
        do {
            try testControllerLoadsPersistedStoreAndRefreshesWorkspace()
            try testControllerTogglePinsAndPersistsCurrentWindow()
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
    }

    @MainActor
    private static func testControllerTogglePinsAndPersistsCurrentWindow() throws {
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

        let outcome = try controller.toggleCurrentWindow()
        let reloadedStore = try persistence.loadStore()

        switch outcome {
        case .pinned(let window):
            try expect(
                window.windowTitle == "Spec",
                message: "toggle should pin the focused window through the app controller"
            )
        case .unpinned, .requiresAccessibilityPermission, .noFocusedWindow:
            throw SmokeTestFailure(
                message: "toggle should pin the focused window in the happy path"
            )
        }

        try expect(
            reloadedStore.count == 1,
            message: "toggle should persist the updated pinned-window store"
        )
        try expect(
            controller.presentation().pinnedTitles == ["Spec"],
            message: "presentation should surface the newly pinned window title"
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
