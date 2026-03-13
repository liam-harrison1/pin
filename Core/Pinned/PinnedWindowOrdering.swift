import Foundation

public enum PinnedWindowOrderingMode: Sendable {
    case recentInteractionFirst
    case recentPinFirst
}

public enum PinnedWindowOrdering {
    public static func sort(
        _ windows: [PinnedWindow],
        mode: PinnedWindowOrderingMode
    ) -> [PinnedWindow] {
        windows.sorted { lhs, rhs in
            let lhsDate = primaryDate(for: lhs, mode: mode)
            let rhsDate = primaryDate(for: rhs, mode: mode)

            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }

            if lhs.lastPinnedAt != rhs.lastPinnedAt {
                return lhs.lastPinnedAt > rhs.lastPinnedAt
            }

            if lhs.windowTitle != rhs.windowTitle {
                return lhs.windowTitle.localizedCaseInsensitiveCompare(rhs.windowTitle) == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func primaryDate(
        for window: PinnedWindow,
        mode: PinnedWindowOrderingMode
    ) -> Date {
        switch mode {
        case .recentInteractionFirst:
            return window.lastActivatedAt ?? window.lastPinnedAt
        case .recentPinFirst:
            return window.lastPinnedAt
        }
    }
}
