import Foundation
import DeskPinsAccessibility
import DeskPinsOverlay
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

public struct DeskPinsMenuBarVisibleWindowItem: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var isPinned: Bool

    public init(id: UUID, title: String, isPinned: Bool) {
        self.id = id
        self.title = title
        self.isPinned = isPinned
    }
}

public struct DeskPinsMenuBarPresentation: Sendable, Equatable {
    public var pinnedCount: Int
    public var pinnedWindows: [DeskPinsMenuBarPinnedWindowItem]
    public var visibleWindows: [DeskPinsMenuBarVisibleWindowItem]
    public var accessibilityStatus: AccessibilityTrustStatus
    public var focusStatus: PinningWorkspaceFocusStatus?
    public var focusedWindowTitle: String?
    public var lastRefreshAt: Date?

    public init(
        pinnedCount: Int,
        pinnedWindows: [DeskPinsMenuBarPinnedWindowItem],
        visibleWindows: [DeskPinsMenuBarVisibleWindowItem],
        accessibilityStatus: AccessibilityTrustStatus,
        focusStatus: PinningWorkspaceFocusStatus?,
        focusedWindowTitle: String?,
        lastRefreshAt: Date?
    ) {
        self.pinnedCount = pinnedCount
        self.pinnedWindows = pinnedWindows
        self.visibleWindows = visibleWindows
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
    private let windowActivator: any WindowActivating

    public private(set) var store: PinnedWindowStore
    public private(set) var workspaceSnapshot: PinningWorkspaceSnapshot?
    private var lastFrontmostPinnedWindowID: UUID?
    private var overlayLeaseOwnerID: UUID?
    private var isOverlayLeaseActive = false
    private var suppressedPinnedWindowIDs: Set<UUID> = []
    private var interactionPersistTask: Task<Void, Never>?
    private let interactionPersistDebounceInterval: TimeInterval = 0.8

    public init(
        trustChecker: TrustChecker,
        focusedReader: FocusReader,
        catalogReader: CatalogReader,
        persistence: Persistence,
        windowActivator: any WindowActivating = NoopWindowActivator()
    ) throws {
        self.trustChecker = trustChecker
        self.focusedReader = focusedReader
        self.catalogReader = catalogReader
        self.persistence = persistence
        self.windowActivator = windowActivator
        self.store = try persistence.loadStore()
    }

    public func requestAccessibilityPermission() -> AccessibilityTrustStatus {
        trustChecker.requestAccessIfNeeded()
    }

    public func captureWorkspaceForMenu() throws -> PinningWorkspaceSnapshot {
        let focusCapture = makeCoordinator().captureFocus()
        return try refreshWorkspace(using: focusCapture)
    }

    public func setOverlayInteractionLease(
        ownerID: UUID?,
        active: Bool,
        suppressedWindowIDs: Set<UUID>
    ) {
        guard let ownerID, store.window(id: ownerID) != nil else {
            overlayLeaseOwnerID = nil
            isOverlayLeaseActive = false
            suppressedPinnedWindowIDs.removeAll()
            return
        }

        overlayLeaseOwnerID = ownerID
        isOverlayLeaseActive = active
        guard active else {
            suppressedPinnedWindowIDs.removeAll()
            return
        }

        suppressedPinnedWindowIDs = Set(
            suppressedWindowIDs.filter { id in
                id != ownerID && store.window(id: id) != nil
            }
        )
    }

    public func clearOverlayInteractionLease() {
        overlayLeaseOwnerID = nil
        isOverlayLeaseActive = false
        suppressedPinnedWindowIDs.removeAll()
    }

    public func focusedPinnedWindowID() -> UUID? {
        guard let focusedEntry = workspaceSnapshot?.focusedEntry else {
            return nil
        }

        return store.matchingWindow(for: focusedEntry.asPinnedReference())?.id
    }

    public func focusedPinnedWindowIDUsingLiveFocus() -> UUID? {
        guard let focusedWindow = try? focusedReader.currentFocusedWindow() else {
            return nil
        }

        let focusedReference = focusedWindow.asPinnedReference()
        if let matched = store.matchingWindow(for: focusedReference) {
            return matched.id
        }

        return bestEffortPinnedWindowIDForLiveFocus(reference: focusedReference)
    }

    public func refreshWorkspace() throws -> PinningWorkspaceSnapshot {
        try refreshWorkspace(using: nil)
    }

    public func refreshWorkspaceUsingCachedFocus() throws -> PinningWorkspaceSnapshot {
        try refreshWorkspace(using: currentFocusCapture())
    }

    public func refreshWorkspace(
        using focusCapture: PinningWorkspaceFocusCapture?
    ) throws -> PinningWorkspaceSnapshot {
        var snapshot = try makeCoordinator().refresh(
            store: &store,
            focusCapture: focusCapture,
            at: .now
        )

        updateInteractionOrderingFromFrontmostPinnedWindow(
            visibleEntries: snapshot.visibleEntries,
            at: snapshot.refreshedAt
        )
        snapshot.pinnedWindows = store.orderedWindows(mode: .recentInteractionFirst)

        workspaceSnapshot = snapshot
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

        let reference = workspaceSnapshot?.focusedEntry?.asPinnedReference()
            ?? focusedWindow.asPinnedReference()
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

    @discardableResult
    public func unpinAllWindows() throws -> [PinnedWindow] {
        let removed = store.unpinAll()

        guard !removed.isEmpty else {
            return []
        }

        try persistStore()
        _ = try? refreshWorkspace(using: currentFocusCapture())
        return removed
    }

    public func toggleVisibleWindow(id: UUID) throws -> PinCatalogWindowToggleResult? {
        guard let entry = workspaceSnapshot?.visibleEntries.first(where: { $0.id == id }) else {
            return nil
        }

        let service = PinCatalogWindowService()
        let result = service.toggle(entry: entry, in: &store, at: .now)

        try persistStore()
        _ = try? refreshWorkspace(using: currentFocusCapture())
        return result
    }

    @discardableResult
    public func markPinnedWindowInteracted(
        id: UUID,
        at date: Date = .now
    ) -> PinnedWindow? {
        let activated = store.markActivated(id: id, at: date)
        if activated != nil {
            scheduleInteractionPersistence()
        }
        return activated
    }

    @discardableResult
    public func activatePinnedWindow(id: UUID) throws -> PinnedWindow? {
        guard let window = store.window(id: id) else {
            return nil
        }

        try windowActivator.activateWindow(reference: window.reference)
        _ = store.markActivated(id: id, at: .now)
        try persistStore()
        _ = try? refreshWorkspace()
        return store.window(id: id)
    }

    @discardableResult
    public func activatePinnedWindowLightweight(id: UUID) throws -> Bool {
        guard let window = store.window(id: id) else {
            return false
        }

        try windowActivator.activateWindow(reference: window.reference)
        _ = store.markActivated(id: id, at: .now)
        scheduleInteractionPersistence()
        return true
    }

    public func presentation() -> DeskPinsMenuBarPresentation {
        let orderedWindows = store.orderedWindows(mode: .recentInteractionFirst)
        let visibleEntries = workspaceSnapshot?.visibleEntries ?? []

        return DeskPinsMenuBarPresentation(
            pinnedCount: orderedWindows.count,
            pinnedWindows: orderedWindows.map { window in
                DeskPinsMenuBarPinnedWindowItem(
                    id: window.id,
                    title: window.windowTitle,
                    isInvalidated: window.isInvalidated
                )
            },
            visibleWindows: visibleEntries.prefix(8).map { entry in
                DeskPinsMenuBarVisibleWindowItem(
                    id: entry.id,
                    title: entry.effectiveTitle,
                    isPinned: store.matchingWindow(for: entry.asPinnedReference()) != nil
                )
            },
            accessibilityStatus: trustChecker.currentStatus(),
            focusStatus: workspaceSnapshot?.focusStatus,
            focusedWindowTitle: workspaceSnapshot?.focusedWindow?.effectiveTitle,
            lastRefreshAt: workspaceSnapshot?.refreshedAt
        )
    }

    public func overlayTargets() -> [PinnedWindowOverlayTarget] {
        let visibleEntries = workspaceSnapshot?.visibleEntries ?? []
        let orderedWindows = store.orderedWindows(mode: .recentInteractionFirst)

        return orderedWindows.compactMap { pinnedWindow in
            let renderPolicy = overlayRenderPolicy(for: pinnedWindow.id)
            if let visibleEntry = visibleEntries.first(where: { entry in
                pinnedWindow.reference.likelyMatches(entry.asPinnedReference())
            }) {
                return PinnedWindowOverlayTarget(
                    id: pinnedWindow.id,
                    title: pinnedWindow.windowTitle,
                    frame: CGRect(
                        x: visibleEntry.bounds.x,
                        y: visibleEntry.bounds.y,
                        width: visibleEntry.bounds.width,
                        height: visibleEntry.bounds.height
                    ),
                    isStale: pinnedWindow.isInvalidated,
                    renderPolicy: renderPolicy,
                    reference: pinnedWindow.reference
                )
            }

            guard let bounds = pinnedWindow.bounds else {
                return nil
            }

            return PinnedWindowOverlayTarget(
                id: pinnedWindow.id,
                title: pinnedWindow.windowTitle,
                frame: CGRect(
                    x: bounds.x,
                    y: bounds.y,
                    width: bounds.width,
                    height: bounds.height
                ),
                isStale: pinnedWindow.isInvalidated,
                renderPolicy: renderPolicy,
                reference: pinnedWindow.reference
            )
        }
    }

    public func overlappingPinnedWindowIDs(for id: UUID) -> Set<UUID> {
        let visibleEntries = workspaceSnapshot?.visibleEntries ?? []
        let orderedWindows = store.orderedWindows(mode: .recentInteractionFirst)

        guard let owner = orderedWindows.first(where: { $0.id == id }),
              let ownerFrame = liveFrameForPinnedWindow(owner, visibleEntries: visibleEntries) else {
            return []
        }

        let overlapInsets: CGFloat = 2
        let matchFrame = ownerFrame.insetBy(dx: -overlapInsets, dy: -overlapInsets)
        var overlappingIDs: Set<UUID> = []

        for window in orderedWindows where window.id != id {
            guard let frame = liveFrameForPinnedWindow(window, visibleEntries: visibleEntries) else {
                continue
            }

            let intersection = frame.intersection(matchFrame)
            guard !intersection.isNull else {
                continue
            }

            let overlapArea = intersection.width * intersection.height
            let minArea = min(
                ownerFrame.width * ownerFrame.height,
                frame.width * frame.height
            )
            let requiredArea = max(2_000, minArea * 0.01)
            guard overlapArea >= requiredArea else {
                continue
            }
            overlappingIDs.insert(window.id)
        }

        return overlappingIDs
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

    private func updateInteractionOrderingFromFrontmostPinnedWindow(
        visibleEntries: [WindowCatalogEntry],
        at date: Date
    ) {
        // While an overlay interaction lease is active/acquiring, keep user-chosen
        // interaction priority stable and do not let catalog refresh reorder it.
        guard overlayLeaseOwnerID == nil else {
            return
        }

        let frontmostPinnedWindowID = visibleEntries.compactMap { entry in
            store.matchingWindow(for: entry.asPinnedReference())?.id
        }.first

        guard frontmostPinnedWindowID != lastFrontmostPinnedWindowID else {
            return
        }

        lastFrontmostPinnedWindowID = frontmostPinnedWindowID
        guard let frontmostPinnedWindowID else {
            return
        }

        _ = store.markActivated(id: frontmostPinnedWindowID, at: date)
    }

    private func overlayRenderPolicy(for id: UUID) -> PinnedWindowOverlayRenderPolicy {
        if suppressedPinnedWindowIDs.contains(id) {
            return .suppressed
        }

        if isOverlayLeaseActive, overlayLeaseOwnerID == id {
            return .directInteractionOwner
        }

        return .mirrorVisible
    }

    private func frameForPinnedWindow(
        _ pinnedWindow: PinnedWindow,
        visibleEntries: [WindowCatalogEntry]
    ) -> CGRect? {
        if let visibleEntry = visibleEntries.first(where: { entry in
            pinnedWindow.reference.likelyMatches(entry.asPinnedReference())
        }) {
            return CGRect(
                x: visibleEntry.bounds.x,
                y: visibleEntry.bounds.y,
                width: visibleEntry.bounds.width,
                height: visibleEntry.bounds.height
            )
        }

        guard let bounds = pinnedWindow.bounds else {
            return nil
        }

        return CGRect(
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: bounds.height
        )
    }

    private func liveFrameForPinnedWindow(
        _ pinnedWindow: PinnedWindow,
        visibleEntries: [WindowCatalogEntry]
    ) -> CGRect? {
        guard let visibleEntry = visibleEntries.first(where: { entry in
            pinnedWindow.reference.likelyMatches(entry.asPinnedReference())
        }) else {
            return nil
        }

        return CGRect(
            x: visibleEntry.bounds.x,
            y: visibleEntry.bounds.y,
            width: visibleEntry.bounds.width,
            height: visibleEntry.bounds.height
        )
    }

    private func bestEffortPinnedWindowIDForLiveFocus(
        reference focusedReference: PinnedWindowReference
    ) -> UUID? {
        let sameProcessWindows = store.allWindows.filter { window in
            window.reference.ownerPID == focusedReference.ownerPID
        }
        guard !sameProcessWindows.isEmpty else {
            return nil
        }
        if sameProcessWindows.count == 1 {
            return sameProcessWindows.first?.id
        }

        guard let focusedBounds = focusedReference.bounds else {
            return nil
        }

        let scoredWindows = sameProcessWindows.compactMap { window -> (id: UUID, score: Double)? in
            guard let candidateBounds = window.reference.bounds else {
                return nil
            }
            let score = boundsDistanceScore(
                lhs: candidateBounds,
                rhs: focusedBounds
            )
            return (id: window.id, score: score)
        }.sorted { lhs, rhs in
            lhs.score < rhs.score
        }

        guard let best = scoredWindows.first else {
            return nil
        }
        if scoredWindows.count == 1 {
            return best.id
        }

        let runnerUp = scoredWindows[1]
        let separation = runnerUp.score - best.score
        if best.score <= 320 && separation >= 120 {
            return best.id
        }

        return nil
    }

    private func boundsDistanceScore(
        lhs: PinnedWindowBounds,
        rhs: PinnedWindowBounds
    ) -> Double {
        abs(lhs.x - rhs.x)
            + abs(lhs.y - rhs.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private func persistStore() throws {
        _ = try persistence.saveStore(store, savedAt: .now)
    }

    private func scheduleInteractionPersistence() {
        interactionPersistTask?.cancel()
        let delayNanoseconds = UInt64(
            interactionPersistDebounceInterval * 1_000_000_000
        )
        interactionPersistTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            self.interactionPersistTask = nil
            try? self.persistStore()
        }
    }
}
