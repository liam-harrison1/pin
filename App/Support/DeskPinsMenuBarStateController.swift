import Foundation
import DeskPinsAccessibility
import DeskPinsPinning
import DeskPinsPinned
import DeskPinsWindowCatalog

public struct DeskPinsMenuBarPinnedWindowItem: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var isInvalidated: Bool

    public init(id: UUID, title: String, isInvalidated: Bool) {
        self.id = id
        self.title = title
        self.isInvalidated = isInvalidated
    }
}

public struct DeskPinsMenuBarPresentation: Sendable, Equatable {
    public var pinnedCount: Int
    public var pinnedWindows: [DeskPinsMenuBarPinnedWindowItem]
    public var accessibilityStatus: AccessibilityTrustStatus
    public var focusStatus: PinningWorkspaceFocusStatus?
    public var focusedWindowTitle: String?
    public var lastRefreshAt: Date?

    public init(
        pinnedCount: Int,
        pinnedWindows: [DeskPinsMenuBarPinnedWindowItem],
        accessibilityStatus: AccessibilityTrustStatus,
        focusStatus: PinningWorkspaceFocusStatus?,
        focusedWindowTitle: String?,
        lastRefreshAt: Date?
    ) {
        self.pinnedCount = pinnedCount
        self.pinnedWindows = pinnedWindows
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

    public func captureWorkspaceForMenu() throws -> PinningWorkspaceSnapshot {
        let focusCapture = makeCoordinator().captureFocus()
        return try refreshWorkspace(using: focusCapture)
    }

    public func refreshWorkspace() throws -> PinningWorkspaceSnapshot {
        try refreshWorkspace(using: nil)
    }

    public func refreshWorkspace(
        using focusCapture: PinningWorkspaceFocusCapture?
    ) throws -> PinningWorkspaceSnapshot {
        let snapshot = try makeCoordinator().refresh(
            store: &store,
            focusCapture: focusCapture,
            at: .now
        )
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

    @discardableResult
    public func togglePresentedFocusedWindow() throws -> PinCurrentWindowActionOutcome {
        let focusCapture = currentFocusCapture() ?? makeCoordinator().captureFocus()

        guard let focusedWindow = focusCapture.focusedWindow else {
            return mapFocusStatusToOutcome(focusCapture.status)
        }

        let reference = focusedWindow.asPinnedReference()
        let outcome: PinCurrentWindowActionOutcome

        if let unpinned = store.unpin(reference: reference) {
            outcome = .unpinned(unpinned)
        } else {
            let pinned = store.pin(reference: reference, at: .now)
            outcome = .pinned(pinned)
        }

        try persistStore()
        _ = try? refreshWorkspace(using: focusCapture)
        return outcome
    }

    @discardableResult
    public func unpinWindow(id: UUID) throws -> PinnedWindow? {
        let removed = store.unpin(id: id)

        guard removed != nil else {
            return nil
        }

        try persistStore()
        _ = try? refreshWorkspace(using: currentFocusCapture())
        return removed
    }

    public func presentation() -> DeskPinsMenuBarPresentation {
        let orderedWindows = store.orderedWindows(mode: .recentInteractionFirst)

        return DeskPinsMenuBarPresentation(
            pinnedCount: orderedWindows.count,
            pinnedWindows: orderedWindows.map { window in
                DeskPinsMenuBarPinnedWindowItem(
                    id: window.id,
                    title: window.windowTitle,
                    isInvalidated: window.isInvalidated
                )
            },
            accessibilityStatus: trustChecker.currentStatus(),
            focusStatus: workspaceSnapshot?.focusStatus,
            focusedWindowTitle: workspaceSnapshot?.focusedWindow?.effectiveTitle,
            lastRefreshAt: workspaceSnapshot?.refreshedAt
        )
    }

    private func makeCoordinator() -> PinningWorkspaceCoordinator<CatalogReader, FocusReader> {
        PinningWorkspaceCoordinator(
            catalogReader: catalogReader,
            focusedWindowReader: focusedReader
        )
    }

    private func currentFocusCapture() -> PinningWorkspaceFocusCapture? {
        guard let workspaceSnapshot else {
            return nil
        }

        return PinningWorkspaceFocusCapture(
            status: workspaceSnapshot.focusStatus,
            focusedWindow: workspaceSnapshot.focusedWindow
        )
    }

    private func mapFocusStatusToOutcome(
        _ status: PinningWorkspaceFocusStatus
    ) -> PinCurrentWindowActionOutcome {
        switch status {
        case .available, .noFocusedWindow:
            return .noFocusedWindow
        case .requiresAccessibilityPermission:
            return .requiresAccessibilityPermission
        }
    }

    private func persistStore() throws {
        _ = try persistence.saveStore(store, savedAt: .now)
    }
}
