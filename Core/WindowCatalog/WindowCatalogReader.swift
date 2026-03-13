@preconcurrency import CoreGraphics
import Foundation

public enum WindowCatalogReadError: Error, Sendable, Equatable, CustomStringConvertible {
    case catalogUnavailable
    case malformedEntry(String)

    public var description: String {
        switch self {
        case .catalogUnavailable:
            return "CoreGraphics did not return a window catalog."
        case .malformedEntry(let detail):
            return "Malformed window catalog entry: \(detail)"
        }
    }
}

public protocol WindowCatalogReading: Sendable {
    func currentWindowCatalog() throws -> WindowCatalog
}

public struct WindowCatalogReaderOptions: Sendable, Equatable {
    public var listOptionsRawValue: UInt32
    public var relativeToWindowIDRawValue: UInt32

    public init(
        listOptionsRawValue: UInt32 = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements).rawValue,
        relativeToWindowIDRawValue: UInt32 = 0
    ) {
        self.listOptionsRawValue = listOptionsRawValue
        self.relativeToWindowIDRawValue = relativeToWindowIDRawValue
    }

    public var listOptions: CGWindowListOption {
        CGWindowListOption(rawValue: listOptionsRawValue)
    }

    public var relativeToWindowID: CGWindowID {
        CGWindowID(relativeToWindowIDRawValue)
    }
}

public struct StaticWindowCatalogReader: WindowCatalogReading {
    public let catalog: WindowCatalog

    public init(catalog: WindowCatalog) {
        self.catalog = catalog
    }

    public func currentWindowCatalog() throws -> WindowCatalog {
        catalog
    }
}

public struct LiveWindowCatalogReader: WindowCatalogReading {
    public var options: WindowCatalogReaderOptions

    public init(options: WindowCatalogReaderOptions = .init()) {
        self.options = options
    }

    public func currentWindowCatalog() throws -> WindowCatalog {
        guard let rawWindowList = CGWindowListCopyWindowInfo(
            options.listOptions,
            options.relativeToWindowID
        ) as? [[String: Any]] else {
            throw WindowCatalogReadError.catalogUnavailable
        }

        let entries = rawWindowList.enumerated().compactMap { index, rawEntry in
            try? WindowCatalogEntryParser.parse(rawEntry, frontToBackIndex: index)
        }

        return WindowCatalog(entries: entries)
    }
}

public enum WindowCatalogEntryParser {
    public static func parse(
        _ rawEntry: [String: Any],
        frontToBackIndex: Int
    ) throws -> WindowCatalogEntry {
        guard let ownerPID = int32Value(for: key(.ownerPID), in: rawEntry) else {
            throw WindowCatalogReadError.malformedEntry("missing owner PID")
        }

        guard let ownerName = stringValue(for: key(.ownerName), in: rawEntry)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !ownerName.isEmpty else {
            throw WindowCatalogReadError.malformedEntry("missing owner name")
        }

        guard let boundsDictionary = rawEntry[key(.bounds)] as? [String: Any],
              let bounds = parseBounds(boundsDictionary) else {
            throw WindowCatalogReadError.malformedEntry("missing bounds")
        }

        return WindowCatalogEntry(
            frontToBackIndex: frontToBackIndex,
            ownerPID: ownerPID,
            ownerName: ownerName,
            windowTitle: stringValue(for: key(.title), in: rawEntry) ?? "",
            windowNumber: intValue(for: key(.number), in: rawEntry),
            layer: intValue(for: key(.layer), in: rawEntry) ?? 0,
            alpha: doubleValue(for: key(.alpha), in: rawEntry) ?? 1,
            bounds: bounds,
            isOnScreen: boolValue(for: key(.isOnScreen), in: rawEntry) ?? true
        )
    }

    private enum RawKey {
        case number
        case layer
        case bounds
        case alpha
        case ownerPID
        case ownerName
        case title
        case isOnScreen
    }

    private static func key(_ rawKey: RawKey) -> String {
        switch rawKey {
        case .number:
            return kCGWindowNumber as String
        case .layer:
            return kCGWindowLayer as String
        case .bounds:
            return kCGWindowBounds as String
        case .alpha:
            return kCGWindowAlpha as String
        case .ownerPID:
            return kCGWindowOwnerPID as String
        case .ownerName:
            return kCGWindowOwnerName as String
        case .title:
            return kCGWindowName as String
        case .isOnScreen:
            return kCGWindowIsOnscreen as String
        }
    }

    private static func parseBounds(_ dictionary: [String: Any]) -> WindowCatalogBounds? {
        guard
            let x = doubleValue(for: "X", in: dictionary),
            let y = doubleValue(for: "Y", in: dictionary),
            let width = doubleValue(for: "Width", in: dictionary),
            let height = doubleValue(for: "Height", in: dictionary)
        else {
            return nil
        }

        return WindowCatalogBounds(x: x, y: y, width: width, height: height)
    }

    private static func stringValue(for key: String, in dictionary: [String: Any]) -> String? {
        if let string = dictionary[key] as? String {
            return string
        }

        return nil
    }

    private static func int32Value(for key: String, in dictionary: [String: Any]) -> Int32? {
        if let number = dictionary[key] as? NSNumber {
            return number.int32Value
        }

        if let intValue = dictionary[key] as? Int {
            return Int32(intValue)
        }

        return nil
    }

    private static func intValue(for key: String, in dictionary: [String: Any]) -> Int? {
        if let number = dictionary[key] as? NSNumber {
            return number.intValue
        }

        return dictionary[key] as? Int
    }

    private static func doubleValue(for key: String, in dictionary: [String: Any]) -> Double? {
        if let number = dictionary[key] as? NSNumber {
            return number.doubleValue
        }

        return dictionary[key] as? Double
    }

    private static func boolValue(for key: String, in dictionary: [String: Any]) -> Bool? {
        if let number = dictionary[key] as? NSNumber {
            return number.boolValue
        }

        return dictionary[key] as? Bool
    }
}
