import Foundation
import DeskPinsAccessibility
import DeskPinsPinning
import DeskPinsPinned

@main
struct DeskPinsPinningSmokeTests {
    static func main() {
        do {
            try testPinCurrentWindowCreatesPinnedEntry()
            try testToggleCurrentWindowUnpinsMatchingEntry()
            try testUnpinCurrentWindowReturnsNilWhenNotPinned()
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
            try expect(window.windowTitle == "Logs", message: "toggle should return the unpinned current window when it was already pinned")
            try expect(store.isEmpty, message: "toggle should remove the current window when it was already pinned")
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
