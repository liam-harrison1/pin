import Foundation
import CoreGraphics
import DeskPinsPinned
import DeskPinsWindowCatalog

@main
struct DeskPinsWindowCatalogSmokeTests {
    static func main() {
        do {
            try testFilteringKeepsLikelyUserWindows()
            try testSearchPrioritizesWindowTitleMatches()
            try testTopmostEntryUsesFrontToBackOrdering()
            try testPinnedReferencePreservesWeakIdentityFields()
            try testParserBuildsEntryFromCoreGraphicsStyleDictionary()
            try testStaticReaderReturnsConfiguredCatalog()
            print("DeskPinsWindowCatalog smoke tests passed")
        } catch {
            fputs("Window catalog smoke test failure: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func testFilteringKeepsLikelyUserWindows() throws {
        let catalog = WindowCatalog(entries: [
            WindowCatalogEntry(
                frontToBackIndex: 0,
                ownerPID: 10,
                ownerName: "Dock",
                windowTitle: "",
                windowNumber: 1,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 0, y: 0, width: 100, height: 100),
                isOnScreen: true
            ),
            WindowCatalogEntry(
                frontToBackIndex: 1,
                ownerPID: 11,
                ownerName: "Notes",
                windowTitle: "Meeting Notes",
                windowNumber: 2,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 10, y: 10, width: 400, height: 300),
                isOnScreen: true
            ),
            WindowCatalogEntry(
                frontToBackIndex: 2,
                ownerPID: 12,
                ownerName: "Browser",
                windowTitle: "Docs",
                windowNumber: 3,
                layer: 3,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 20, y: 20, width: 400, height: 300),
                isOnScreen: true
            )
        ])

        let filtered = catalog.filteredEntries()
        try expect(filtered.map(\.ownerName) == ["Notes"], message: "default filtering should keep standard on-screen user windows and drop known noise")
    }

    private static func testSearchPrioritizesWindowTitleMatches() throws {
        let catalog = WindowCatalog(entries: [
            WindowCatalogEntry(
                frontToBackIndex: 1,
                ownerPID: 20,
                ownerName: "Safari",
                windowTitle: "Accessibility API Guide",
                windowNumber: 10,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 0, y: 0, width: 600, height: 400),
                isOnScreen: true
            ),
            WindowCatalogEntry(
                frontToBackIndex: 0,
                ownerPID: 21,
                ownerName: "Accessibility Inspector",
                windowTitle: "Results",
                windowNumber: 11,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 10, y: 10, width: 500, height: 400),
                isOnScreen: true
            )
        ])

        let results = catalog.search("accessibility")
        try expect(results.map(\.windowNumber) == [10, 11], message: "title matches should rank ahead of owner-name-only matches")
    }

    private static func testTopmostEntryUsesFrontToBackOrdering() throws {
        let point = WindowCatalogPoint(x: 50, y: 50)
        let catalog = WindowCatalog(entries: [
            WindowCatalogEntry(
                frontToBackIndex: 1,
                ownerPID: 31,
                ownerName: "Editor",
                windowTitle: "Back",
                windowNumber: 20,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 0, y: 0, width: 200, height: 200),
                isOnScreen: true
            ),
            WindowCatalogEntry(
                frontToBackIndex: 0,
                ownerPID: 32,
                ownerName: "Terminal",
                windowTitle: "Front",
                windowNumber: 21,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 0, y: 0, width: 200, height: 200),
                isOnScreen: true
            )
        ])

        let topmost = catalog.topmostEntry(containing: point)
        try expect(topmost?.windowNumber == 21, message: "hit testing should return the frontmost matching entry")
    }

    private static func testPinnedReferencePreservesWeakIdentityFields() throws {
        let entry = WindowCatalogEntry(
            frontToBackIndex: 0,
            ownerPID: 40,
            ownerName: "Notes",
            windowTitle: "Sprint Plan",
            windowNumber: 77,
            layer: 0,
            alpha: 1,
            bounds: WindowCatalogBounds(x: 1, y: 2, width: 300, height: 200),
            isOnScreen: true
        )

        let reference = entry.asPinnedReference()
        try expect(reference.ownerPID == 40, message: "pinned reference should preserve owner pid")
        try expect(reference.windowNumber == 77, message: "pinned reference should preserve window number when available")
        try expect(reference.windowTitle == "Sprint Plan", message: "pinned reference should preserve effective title")
        try expect(reference.bounds == PinnedWindowBounds(x: 1, y: 2, width: 300, height: 200), message: "pinned reference should preserve bounds snapshot")
    }

    private static func testParserBuildsEntryFromCoreGraphicsStyleDictionary() throws {
        let rawEntry: [String: Any] = [
            kCGWindowOwnerPID as String: 50,
            kCGWindowOwnerName as String: "Terminal",
            kCGWindowName as String: "Logs",
            kCGWindowNumber as String: 88,
            kCGWindowLayer as String: 0,
            kCGWindowAlpha as String: 1,
            kCGWindowIsOnscreen as String: true,
            kCGWindowBounds as String: [
                "X": 10,
                "Y": 20,
                "Width": 700,
                "Height": 500
            ]
        ]

        let entry = try WindowCatalogEntryParser.parse(rawEntry, frontToBackIndex: 3)
        try expect(entry.ownerPID == 50, message: "parser should preserve owner PID")
        try expect(entry.windowNumber == 88, message: "parser should preserve window number")
        try expect(entry.bounds == WindowCatalogBounds(x: 10, y: 20, width: 700, height: 500), message: "parser should decode CoreGraphics-style bounds dictionaries")
    }

    private static func testStaticReaderReturnsConfiguredCatalog() throws {
        let catalog = WindowCatalog(entries: [
            WindowCatalogEntry(
                frontToBackIndex: 0,
                ownerPID: 60,
                ownerName: "Notes",
                windowTitle: "Backlog",
                windowNumber: 90,
                layer: 0,
                alpha: 1,
                bounds: WindowCatalogBounds(x: 0, y: 0, width: 100, height: 100),
                isOnScreen: true
            )
        ])
        let reader = StaticWindowCatalogReader(catalog: catalog)

        let readCatalog = try reader.currentWindowCatalog()
        try expect(readCatalog.entries == catalog.entries, message: "static window catalog reader should return the configured catalog")
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
