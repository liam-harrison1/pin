import Foundation
import DeskPinsPinned

@main
struct DeskPinsPinnedSmokeTests {
    static func main() {
        do {
            try testRecentInteractionWins()
            try testRecentPinWins()
            try testFallbackToPinTime()
            try testPinningSameWindowUpdatesExistingEntry()
            try testActivationReordersStoreResults()
            try testInvalidationAndUnpinLifecycle()
            print("DeskPinsPinned smoke tests passed")
        } catch {
            fputs("Smoke test failure: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func testRecentInteractionWins() throws {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        let earlier = PinnedWindow(
            reference: PinnedWindowReference(ownerPID: 1, windowTitle: "Earlier"),
            lastPinnedAt: baseDate,
            lastActivatedAt: baseDate.addingTimeInterval(5)
        )
        let later = PinnedWindow(
            reference: PinnedWindowReference(ownerPID: 2, windowTitle: "Later"),
            lastPinnedAt: baseDate.addingTimeInterval(10),
            lastActivatedAt: baseDate.addingTimeInterval(20)
        )

        let ordered = PinnedWindowOrdering.sort(
            [earlier, later],
            mode: .recentInteractionFirst
        )

        try expect(
            ordered.map(\.windowTitle) == ["Later", "Earlier"],
            message: "recent interaction ordering should put the most recently activated window first"
        )
    }

    private static func testRecentPinWins() throws {
        let baseDate = Date(timeIntervalSince1970: 2_000)
        let oldPinNewInteraction = PinnedWindow(
            reference: PinnedWindowReference(ownerPID: 10, windowTitle: "Old Pin"),
            lastPinnedAt: baseDate,
            lastActivatedAt: baseDate.addingTimeInterval(60)
        )
        let newPin = PinnedWindow(
            reference: PinnedWindowReference(ownerPID: 11, windowTitle: "New Pin"),
            lastPinnedAt: baseDate.addingTimeInterval(30),
            lastActivatedAt: nil
        )

        let ordered = PinnedWindowOrdering.sort(
            [oldPinNewInteraction, newPin],
            mode: .recentPinFirst
        )

        try expect(
            ordered.map(\.windowTitle) == ["New Pin", "Old Pin"],
            message: "recent pin ordering should put the newest pin first"
        )
    }

    private static func testFallbackToPinTime() throws {
        let baseDate = Date(timeIntervalSince1970: 3_000)
        let olderPin = PinnedWindow(
            reference: PinnedWindowReference(ownerPID: 21, windowTitle: "Older"),
            lastPinnedAt: baseDate
        )
        let newerPin = PinnedWindow(
            reference: PinnedWindowReference(ownerPID: 22, windowTitle: "Newer"),
            lastPinnedAt: baseDate.addingTimeInterval(15)
        )

        let ordered = PinnedWindowOrdering.sort(
            [olderPin, newerPin],
            mode: .recentInteractionFirst
        )

        try expect(
            ordered.map(\.windowTitle) == ["Newer", "Older"],
            message: "ordering should fall back to pin time when no interaction timestamp is present"
        )
    }

    private static func testPinningSameWindowUpdatesExistingEntry() throws {
        let baseDate = Date(timeIntervalSince1970: 4_000)
        var store = PinnedWindowStore()
        let reference = PinnedWindowReference(
            ownerPID: 42,
            windowTitle: "Notes",
            windowNumber: 99
        )

        let firstPin = store.pin(reference: reference, at: baseDate)
        let secondPin = store.pin(reference: reference, at: baseDate.addingTimeInterval(30))

        try expect(
            store.count == 1,
            message: "pinning the same logical window should not duplicate entries"
        )
        try expect(
            firstPin.id == secondPin.id,
            message: "pinning the same logical window should preserve the original pinned id"
        )
        try expect(
            secondPin.lastPinnedAt == baseDate.addingTimeInterval(30),
            message: "repinning should refresh pin time"
        )
        try expect(
            secondPin.invalidation == nil,
            message: "repinning should clear invalidation state"
        )
    }

    private static func testActivationReordersStoreResults() throws {
        let baseDate = Date(timeIntervalSince1970: 5_000)
        var store = PinnedWindowStore()
        let first = store.pin(
            reference: PinnedWindowReference(ownerPID: 51, windowTitle: "Browser"),
            at: baseDate
        )
        let second = store.pin(
            reference: PinnedWindowReference(ownerPID: 52, windowTitle: "Editor"),
            at: baseDate.addingTimeInterval(5)
        )

        _ = store.markActivated(id: first.id, at: baseDate.addingTimeInterval(50))

        let ordered = store.orderedWindows(mode: .recentInteractionFirst)
        try expect(
            ordered.map(\.id) == [first.id, second.id],
            message: "activating a pinned window should move it to the front in interaction ordering"
        )
    }

    private static func testInvalidationAndUnpinLifecycle() throws {
        let baseDate = Date(timeIntervalSince1970: 6_000)
        var store = PinnedWindowStore()
        let pinned = store.pin(
            reference: PinnedWindowReference(ownerPID: 61, windowTitle: "Terminal"),
            at: baseDate
        )

        let invalidated = store.markInvalidated(
            id: pinned.id,
            reason: .windowClosed,
            at: baseDate.addingTimeInterval(10)
        )
        try expect(
            invalidated?.isInvalidated == true,
            message: "invalidating a pinned window should retain it with invalidation metadata"
        )

        let removed = store.unpin(id: pinned.id)
        try expect(
            removed?.id == pinned.id,
            message: "unpin should remove and return the pinned window"
        )
        try expect(
            store.isEmpty,
            message: "store should be empty after removing the only pinned window"
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
