import Foundation
import DeskPinsAccessibility
import DeskPinsPinned

@main
struct DeskPinsAccessibilitySmokeTests {
    static func main() {
        do {
            try testStaticTrustCheckerReportsConfiguredStatus()
            try testStaticReaderReturnsSnapshot()
            try testSnapshotFallsBackToApplicationName()
            try testSnapshotConvertsToPinnedReference()
            print("DeskPinsAccessibility smoke tests passed")
        } catch {
            fputs("Accessibility smoke test failure: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func testStaticTrustCheckerReportsConfiguredStatus() throws {
        let trustedChecker = StaticAccessibilityTrustChecker(status: .trusted)
        let untrustedChecker = StaticAccessibilityTrustChecker(status: .notTrusted)

        try expect(trustedChecker.currentStatus() == .trusted, message: "static trust checker should return its configured trusted status")
        try expect(untrustedChecker.requestAccessIfNeeded() == .notTrusted, message: "static trust checker should return its configured untrusted status")
    }

    private static func testStaticReaderReturnsSnapshot() throws {
        let snapshot = FocusedWindowSnapshot(
            ownerPID: 91,
            applicationName: "Notes",
            windowTitle: "Sprint Notes",
            bounds: PinnedWindowBounds(x: 10, y: 20, width: 640, height: 480)
        )
        let reader = StaticFocusedWindowReader(snapshot: snapshot)

        let readSnapshot = try reader.currentFocusedWindow()
        try expect(readSnapshot == snapshot, message: "static focused window reader should return the configured snapshot")
    }

    private static func testSnapshotFallsBackToApplicationName() throws {
        let snapshot = FocusedWindowSnapshot(
            ownerPID: 92,
            applicationName: "Safari",
            windowTitle: "   "
        )

        try expect(snapshot.effectiveTitle == "Safari", message: "effective title should fall back to application name when the window title is blank")
    }

    private static func testSnapshotConvertsToPinnedReference() throws {
        let snapshot = FocusedWindowSnapshot(
            ownerPID: 93,
            applicationName: "Terminal",
            windowTitle: "Logs",
            bounds: PinnedWindowBounds(x: 1, y: 2, width: 300, height: 200)
        )

        let reference = snapshot.asPinnedReference()
        try expect(reference.ownerPID == 93, message: "focused window snapshot should preserve owner pid")
        try expect(reference.windowTitle == "Logs", message: "focused window snapshot should preserve the effective title in pinned references")
        try expect(reference.bounds == PinnedWindowBounds(x: 1, y: 2, width: 300, height: 200), message: "focused window snapshot should preserve bounds in pinned references")
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
