import Foundation
import DeskPinsAccessibility
import DeskPinsPinned
import DeskPinsWindowCatalog

public enum PinningWorkspaceFocusStatus: Sendable, Equatable {
    case available
    case requiresAccessibilityPermission
    case noFocusedWindow
}

public struct PinningWorkspaceSnapshot: Sendable {
    public var catalog: WindowCatalog
    public var visibleEntries: [WindowCatalogEntry]
    public var focusedWindow: FocusedWindowSnapshot?
    public var focusedEntry: WindowCatalogEntry?
    public var focusedPinnedWindow: PinnedWindow?
    public var focusStatus: PinningWorkspaceFocusStatus
    public var invalidatedPinnedWindows: [PinnedWindow]
    public var pinnedWindows: [PinnedWindow]
    public var refreshedAt: Date

    public init(
        catalog: WindowCatalog,
        visibleEntries: [WindowCatalogEntry],
        focusedWindow: FocusedWindowSnapshot?,
        focusedEntry: WindowCatalogEntry?,
        focusedPinnedWindow: PinnedWindow?,
        focusStatus: PinningWorkspaceFocusStatus,
        invalidatedPinnedWindows: [PinnedWindow],
        pinnedWindows: [PinnedWindow],
        refreshedAt: Date
    ) {
        self.catalog = catalog
        self.visibleEntries = visibleEntries
        self.focusedWindow = focusedWindow
        self.focusedEntry = focusedEntry
        self.focusedPinnedWindow = focusedPinnedWindow
        self.focusStatus = focusStatus
        self.invalidatedPinnedWindows = invalidatedPinnedWindows
        self.pinnedWindows = pinnedWindows
        self.refreshedAt = refreshedAt
    }
}
