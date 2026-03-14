import Foundation
import DeskPinsAccessibility
import DeskPinsPinning
import DeskPinsPinned
import DeskPinsWindowCatalog

public struct DeskPinsMenuBarPresentation: Sendable, Equatable {
    public var pinnedCount: Int
    public var pinnedTitles: [String]
    public var accessibilityStatus: AccessibilityTrustStatus
    public var focusStatus: PinningWorkspaceFocusStatus?
    public var focusedWindowTitle: String?
    public var lastRefreshAt: Date?

    public init(
        pinnedCount: Int,
        pinnedTitles: [String],
        accessibilityStatus: AccessibilityTrustStatus,
        focusStatus: PinningWorkspaceFocusStatus?,
        focusedWindowTitle: String?,
        lastRefreshAt: Date?
    ) {
        self.pinnedCount = pinnedCount
        self.pinnedTitles = pinnedTitles
        self.accessibilityStatus = accessibilityStatus
        self.focusStatus = focusStatus
        self.focusedWindowTitle = focusedWindowTitle
        self.lastRefreshAt = lastRefreshAt
    }
}

@MainActor
public final class DeskPinsMenuBarStateController<
    TrustChecker: AccessibilityTrustChecking,
    FocusReader: FocusedWindowReading,
    CatalogReader: WindowCatalogReading,
    Persistence: PinnedWindowStorePersisting
> {
    private let trustChecker: TrustChecker
    private let focusedReader: FocusReader
    private let catalogReader: CatalogReader
    private let persistence: Persistence

    public private(set) var store: PinnedWindowStore
    public private(set) var workspaceSnapshot: PinningWorkspaceSnapshot?

    public init(
        trustChecker: TrustChecker,
        focusedReader: FocusReader,
        catalogReader: CatalogReader,
        persistence: Persistence
    ) throws {
        self.trustChecker = trustChecker
        self.focusedReader = focusedReader
        self.catalogReader = catalogReader
        self.persistence = persistence
        self.store = try persistence.loadStore()
    }

    public func requestAccessibilityPermission() -> AccessibilityTrustStatus {
        trustChecker.requestAccessIfNeeded()
    }

    public func refreshWorkspace() throws -> PinningWorkspaceSnapshot {
        let coordinator = PinningWorkspaceCoordinator(
            catalogReader: catalogReader,
            focusedWindowReader: focusedReader
        )
        let snapshot = try coordinator.refresh(store: &store, at: .now)
        workspaceSnapshot = snapshot
        try persistStore()
        return snapshot
    }

    @discardableResult
    public func toggleCurrentWindow() throws -> PinCurrentWindowActionOutcome {
        let service = PinCurrentWindowService(reader: focusedReader)
        let outcome = service.attemptToggleCurrentWindow(in: &store, at: .now)

        switch outcome {
        case .pinned, .unpinned:
            try persistStore()
            _ = try? refreshWorkspace()
        case .requiresAccessibilityPermission, .noFocusedWindow:
            break
        }

        return outcome
    }

    public func presentation() -> DeskPinsMenuBarPresentation {
        let orderedWindows = store.orderedWindows(mode: .recentInteractionFirst)

        return DeskPinsMenuBarPresentation(
            pinnedCount: orderedWindows.count,
            pinnedTitles: orderedWindows.map(\.windowTitle),
            accessibilityStatus: trustChecker.currentStatus(),
            focusStatus: workspaceSnapshot?.focusStatus,
            focusedWindowTitle: workspaceSnapshot?.focusedWindow?.effectiveTitle,
            lastRefreshAt: workspaceSnapshot?.refreshedAt
        )
    }

    private func persistStore() throws {
        _ = try persistence.saveStore(store, savedAt: .now)
    }
}
