import Foundation

public struct WindowCatalogFilteringRules: Sendable, Equatable {
    public var excludedOwnerNames: Set<String>
    public var minimumAlpha: Double
    public var requireOnScreen: Bool
    public var requirePositiveArea: Bool
    public var allowedLayers: Set<Int>

    public init(
        excludedOwnerNames: Set<String> = Self.defaultExcludedOwnerNames,
        minimumAlpha: Double = 0.01,
        requireOnScreen: Bool = true,
        requirePositiveArea: Bool = true,
        allowedLayers: Set<Int> = [0]
    ) {
        self.excludedOwnerNames = excludedOwnerNames
        self.minimumAlpha = minimumAlpha
        self.requireOnScreen = requireOnScreen
        self.requirePositiveArea = requirePositiveArea
        self.allowedLayers = allowedLayers
    }

    public static let `default` = WindowCatalogFilteringRules()

    public static let defaultExcludedOwnerNames: Set<String> = [
        "Control Center",
        "Dock",
        "Notification Center",
        "Window Server"
    ]
}

public struct WindowCatalog: Sendable {
    public var entries: [WindowCatalogEntry]

    public init(entries: [WindowCatalogEntry] = []) {
        self.entries = entries
    }

    public func filteredEntries(
        rules: WindowCatalogFilteringRules = .default
    ) -> [WindowCatalogEntry] {
        entries.filter { entry in
            if rules.requireOnScreen && !entry.isOnScreen {
                return false
            }

            if rules.requirePositiveArea && !entry.bounds.hasArea {
                return false
            }

            if entry.alpha < rules.minimumAlpha {
                return false
            }

            if !rules.allowedLayers.contains(entry.layer) {
                return false
            }

            return !rules.excludedOwnerNames.contains(entry.ownerName)
        }
        .sorted { lhs, rhs in
            lhs.frontToBackIndex < rhs.frontToBackIndex
        }
    }

    public func search(
        _ query: String,
        rules: WindowCatalogFilteringRules = .default
    ) -> [WindowCatalogEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseEntries = filteredEntries(rules: rules)

        guard !trimmedQuery.isEmpty else {
            return baseEntries
        }

        let normalizedQuery = trimmedQuery.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: .current
        )

        return baseEntries
            .compactMap { entry -> (WindowCatalogEntry, Int)? in
                let owner = normalize(entry.ownerName)
                let title = normalize(entry.windowTitle)

                if title.contains(normalizedQuery) {
                    return (entry, 0)
                }

                if owner.contains(normalizedQuery) {
                    return (entry, 1)
                }

                if normalize(entry.effectiveTitle).contains(normalizedQuery) {
                    return (entry, 2)
                }

                return nil
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }

                return lhs.0.frontToBackIndex < rhs.0.frontToBackIndex
            }
            .map(\.0)
    }

    public func topmostEntry(
        containing point: WindowCatalogPoint,
        rules: WindowCatalogFilteringRules = .default
    ) -> WindowCatalogEntry? {
        filteredEntries(rules: rules).first { entry in
            entry.bounds.contains(point)
        }
    }

    private func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
