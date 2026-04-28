import Foundation
import DeskPinsPinned

@main
struct DeskPinsPinnedPersistenceSmokeTests {
    static func main() {
        do {
            try testLoadingMissingStoreReturnsEmptyStore()
            try testSaveAndLoadRoundTripPreservesPinnedWindows()
            try testUnsupportedSchemaVersionRecoversToEmptyStore()
            print("DeskPinsPinnedPersistence smoke tests passed")
        } catch {
            fputs("Pinned persistence smoke test failure: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func testLoadingMissingStoreReturnsEmptyStore() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let persistence = JSONPinnedWindowStorePersistence(
            fileURL: tempRoot.appendingPathComponent("PinnedStore.json")
        )

        let loaded = try persistence.loadStore()
        try expect(loaded.isEmpty, message: "loading a missing pinned store should return an empty store")
    }

    private static func testSaveAndLoadRoundTripPreservesPinnedWindows() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("State/PinnedStore.json")
        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)
        let baseDate = Date(timeIntervalSince1970: 11_000)
        var store = PinnedWindowStore()

        let first = store.pin(
            reference: PinnedWindowReference(
                ownerPID: 701,
                windowTitle: "Notes",
                windowNumber: 901
            ),
            at: baseDate
        )
        let second = store.pin(
            reference: PinnedWindowReference(
                ownerPID: 702,
                windowTitle: "Browser",
                windowNumber: 902
            ),
            at: baseDate.addingTimeInterval(5)
        )

        _ = store.markActivated(id: first.id, at: baseDate.addingTimeInterval(10))
        _ = store.markInvalidated(
            id: second.id,
            reason: .noLongerMatched,
            at: baseDate.addingTimeInterval(15)
        )

        let savedSnapshot = try persistence.saveStore(
            store,
            savedAt: baseDate.addingTimeInterval(20)
        )
        let loadedStore = try persistence.loadStore()
        let loadedWindows = loadedStore.orderedWindows(mode: .recentPinFirst)

        try expect(
            FileManager.default.fileExists(atPath: fileURL.path),
            message: "saving a pinned store should create the persistence file"
        )
        try expect(
            savedSnapshot.windows.count == 2,
            message: "saveStore should capture every pinned window in the snapshot"
        )
        try expect(
            loadedWindows.map(\.windowTitle) == ["Browser", "Notes"],
            message: "loading a saved store should preserve the pinned-window set"
        )
        try expect(
            loadedStore.window(id: first.id)?.lastActivatedAt == baseDate.addingTimeInterval(10),
            message: "loading a saved store should preserve interaction metadata"
        )
        try expect(
            loadedStore.window(id: second.id)?.invalidation?.reason == .noLongerMatched,
            message: "loading a saved store should preserve invalidation metadata"
        )
    }

    private static func testUnsupportedSchemaVersionRecoversToEmptyStore() throws {
        let tempRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("PinnedStore.json")
        let snapshot = PinnedWindowStoreSnapshot(
            schemaVersion: 99,
            savedAt: Date(timeIntervalSince1970: 12_000),
            windows: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)

        let persistence = JSONPinnedWindowStorePersistence(fileURL: fileURL)

        let loaded = try persistence.loadStore()
        try expect(
            loaded.isEmpty,
            message: "loading a store with an unsupported schema version should recover with an empty store"
        )
        try expect(
            !FileManager.default.fileExists(atPath: fileURL.path),
            message: "the corrupted store file should be moved to a backup"
        )
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskPinsPinnedPersistence-\(UUID().uuidString)")
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
