import Foundation

public enum PinnedWindowStorePersistenceError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(Int)

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let version):
            return "Unsupported pinned-window store schema version: \(version)"
        }
    }
}

public struct PinnedWindowStoreSnapshot: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var savedAt: Date
    public var windows: [PinnedWindow]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        savedAt: Date = .now,
        windows: [PinnedWindow]
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.windows = windows
    }
}

public protocol PinnedWindowStorePersisting {
    func loadStore() throws -> PinnedWindowStore
    @discardableResult
    func saveStore(
        _ store: PinnedWindowStore,
        savedAt: Date
    ) throws -> PinnedWindowStoreSnapshot
}

public struct JSONPinnedWindowStorePersistence: PinnedWindowStorePersisting {
    public var fileURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func loadStore() throws -> PinnedWindowStore {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return PinnedWindowStore()
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            try? recoverCorruptedStore(error: error)
            return PinnedWindowStore()
        }

        let snapshot: PinnedWindowStoreSnapshot
        do {
            snapshot = try decoder.decode(PinnedWindowStoreSnapshot.self, from: data)
        } catch {
            try? recoverCorruptedStore(error: error)
            return PinnedWindowStore()
        }

        guard snapshot.schemaVersion == PinnedWindowStoreSnapshot.currentSchemaVersion else {
            try? recoverCorruptedStore(
                error: PinnedWindowStorePersistenceError
                    .unsupportedSchemaVersion(snapshot.schemaVersion)
            )
            return PinnedWindowStore()
        }

        return PinnedWindowStore(windows: snapshot.windows)
    }

    private func recoverCorruptedStore(error: Error) throws {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = dateFormatter.string(from: Date())
        let backupURL = fileURL
            .deletingPathExtension()
            .appendingPathExtension("json.bak.\(timestamp)")

        try fileManager.moveItem(at: fileURL, to: backupURL)
    }

    @discardableResult
    public func saveStore(
        _ store: PinnedWindowStore,
        savedAt: Date = .now
    ) throws -> PinnedWindowStoreSnapshot {
        let snapshot = PinnedWindowStoreSnapshot(
            savedAt: savedAt,
            windows: store.orderedWindows(mode: .recentPinFirst)
        )
        let directoryURL = fileURL.deletingLastPathComponent()

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        return snapshot
    }

    public func deletePersistedStore() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }
}
