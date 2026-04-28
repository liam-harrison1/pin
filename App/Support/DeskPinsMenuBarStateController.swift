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

public enum PinnedWindowOverlayContentMode: Sendable, Equatable {
    case badgeOnly
    case mirroredContent
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
    /// Controls the sort order used when presenting pinned windows to the UI.
    public var orderingMode: PinnedWindowOrderingMode = .recentInteractionFirst
    /// Full-window mirror overlays provide the DeskPins-style pinning effect.
    public var overlayContentMode: PinnedWindowOverlayContentMode = .mirroredContent
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

        return resolvePinnedWindowID(for: focusedWindow)
    }

    private func resolvePinnedWindowID(
        for focusedWindow: FocusedWindowSnapshot
    ) -> UUID? {
        switch resolveLiveFocusUsingVisibleWorkspace(snapshot: focusedWindow) {
        case .pinned(let id):
            return id
        case .unpinned:
            return nil
        case .unresolved:
            break
        }

        if let matched = strictPinnedWindowIDForLiveFocus(snapshot: focusedWindow) {
            return matched
        }

        return bestEffortPinnedWindowIDForLiveFocus(snapshot: focusedWindow)
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
        let windowsBeforeRefresh = persistedWindowOrderSnapshot()
        var snapshot = try makeCoordinator().refresh(
            store: &store,
            focusCapture: focusCapture,
            at: .now
        )

        updateInteractionOrderingFromFrontmostPinnedWindow(
            visibleEntries: snapshot.visibleEntries,
            at: snapshot.refreshedAt
        )
        snapshot.pinnedWindows = store.orderedWindows(mode: orderingMode)

        workspaceSnapshot = snapshot
        if windowsBeforeRefresh != persistedWindowOrderSnapshot() {
            try persistStore()
        }
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
        let orderedWindows = store.orderedWindows(mode: orderingMode)
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

    public func overlayTargets(
        overlayOpacity: Double = 0.92,
        overlayClickThrough: Bool = false
    ) -> [PinnedWindowOverlayTarget] {
        let visibleEntries = workspaceSnapshot?.visibleEntries ?? []
        let orderedWindows = store.orderedWindows(mode: .recentInteractionFirst)
        let directInteractionOwnerID = effectiveOverlayInteractionOwnerID()
        let effectiveSuppressedWindowIDs = effectiveSuppressedPinnedWindowIDs(
            ownerID: directInteractionOwnerID
        )

        return orderedWindows.compactMap { pinnedWindow in
            let renderPolicy = overlayRenderPolicy(
                for: pinnedWindow,
                directInteractionOwnerID: directInteractionOwnerID,
                suppressedWindowIDs: effectiveSuppressedWindowIDs
            )
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
                    reference: pinnedWindow.reference,
                    overlayOpacity: overlayOpacity,
                    overlayClickThrough: overlayClickThrough
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
                reference: pinnedWindow.reference,
                overlayOpacity: overlayOpacity,
                overlayClickThrough: overlayClickThrough
            )
        }
    }

    public func overlappingPinnedWindowIDs(for id: UUID) -> Set<UUID> {
        let visibleEntries = workspaceSnapshot?.visibleEntries ?? []
        let orderedWindows = store.orderedWindows(mode: orderingMode)

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

        let frontmostPinnedWindowID = visibleEntries.first.flatMap { entry in
            store.matchingWindow(for: entry.asPinnedReference())?.id
        }

        guard frontmostPinnedWindowID != lastFrontmostPinnedWindowID else {
            return
        }

        lastFrontmostPinnedWindowID = frontmostPinnedWindowID
        guard let frontmostPinnedWindowID else {
            return
        }

        _ = markPinnedWindowInteracted(id: frontmostPinnedWindowID, at: date)
    }

    private func overlayRenderPolicy(
        for pinnedWindow: PinnedWindow,
        directInteractionOwnerID: UUID?,
        suppressedWindowIDs: Set<UUID>
    ) -> PinnedWindowOverlayRenderPolicy {
        if pinnedWindow.isInvalidated || overlayContentMode == .badgeOnly {
            return .badgeOnly
        }

        let id = pinnedWindow.id
        if suppressedWindowIDs.contains(id) {
            return .suppressed
        }

        if directInteractionOwnerID == id {
            return .directInteractionOwner
        }

        return .mirrorVisible
    }

    private func persistedWindowOrderSnapshot() -> [PinnedWindow] {
        store.orderedWindows(mode: .recentPinFirst)
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

    private func effectiveOverlayInteractionOwnerID() -> UUID? {
        if isOverlayLeaseActive {
            return overlayLeaseOwnerID
        }

        guard overlayLeaseOwnerID == nil else {
            return nil
        }

        if let focusedWorkspaceWindowID = focusedPinnedWindowIDUsingWorkspaceFocus() {
            return focusedWorkspaceWindowID
        }

        guard let focusedWindow = workspaceSnapshot?.focusedWindow else {
            return nil
        }

        return resolvePinnedWindowID(for: focusedWindow)
    }

    private func effectiveSuppressedPinnedWindowIDs(ownerID: UUID?) -> Set<UUID> {
        if isOverlayLeaseActive {
            return suppressedPinnedWindowIDs
        }

        guard overlayLeaseOwnerID == nil,
              let ownerID else {
            return []
        }

        return overlappingPinnedWindowIDs(for: ownerID)
    }

    private func focusedPinnedWindowIDUsingWorkspaceFocus() -> UUID? {
        guard let snapshot = workspaceSnapshot,
              let focusedEntry = snapshot.focusedEntry,
              snapshot.visibleEntries.first?.id == focusedEntry.id else {
            return nil
        }

        if let pinnedWindowID = strictPinnedWindowIDForVisibleEntry(focusedEntry) {
            return pinnedWindowID
        }

        return bestEffortPinnedWindowIDForVisibleEntry(focusedEntry)
    }
}

private enum LiveFocusVisibleWorkspaceResolution {
    case unresolved
    case pinned(UUID)
    case unpinned
}

private extension DeskPinsMenuBarStateController {
    func resolveLiveFocusUsingVisibleWorkspace(
        snapshot focusedWindow: FocusedWindowSnapshot
    ) -> LiveFocusVisibleWorkspaceResolution {
        guard let visibleEntries = workspaceSnapshot?.visibleEntries,
              let focusedVisibleEntry = liveFocusedVisibleEntry(
                  snapshot: focusedWindow,
                  visibleEntries: visibleEntries
              ) else {
            return .unresolved
        }

        guard visibleEntries.first?.id == focusedVisibleEntry.id else {
            return .unpinned
        }

        if let pinnedWindowID = strictPinnedWindowIDForVisibleEntry(focusedVisibleEntry) {
            return .pinned(pinnedWindowID)
        }

        if let pinnedWindowID = bestEffortPinnedWindowIDForVisibleEntry(focusedVisibleEntry) {
            return .pinned(pinnedWindowID)
        }

        return .unpinned
    }

    func liveFocusedVisibleEntry(
        snapshot focusedWindow: FocusedWindowSnapshot,
        visibleEntries: [WindowCatalogEntry]
    ) -> WindowCatalogEntry? {
        let sameProcessEntries = visibleEntries.filter { entry in
            entry.ownerPID == focusedWindow.ownerPID
        }
        guard !sameProcessEntries.isEmpty else {
            return nil
        }

        if let windowNumber = focusedWindow.windowNumber {
            return sameProcessEntries.first { entry in
                entry.windowNumber == windowNumber
            }
        }

        guard let focusedBounds = focusedWindow.bounds else {
            return nil
        }

        let focusedTitle = normalizedWindowTitle(focusedWindow.windowTitle)
        if !focusedTitle.isEmpty {
            let exactTitleEntries = sameProcessEntries.filter { entry in
                normalizedWindowTitle(entry.windowTitle) == focusedTitle
            }
            if let matched = nearestVisibleEntry(
                in: exactTitleEntries,
                to: focusedBounds
            ) {
                return matched
            }
        }

        return nearestVisibleEntry(in: sameProcessEntries, to: focusedBounds)
    }

    func strictPinnedWindowIDForVisibleEntry(
        _ visibleEntry: WindowCatalogEntry
    ) -> UUID? {
        let sameProcessWindows = store.allWindows.filter { window in
            window.reference.ownerPID == visibleEntry.ownerPID
        }
        guard !sameProcessWindows.isEmpty else {
            return nil
        }

        if let windowNumber = visibleEntry.windowNumber {
            return sameProcessWindows.first { window in
                window.reference.windowNumber == windowNumber
            }?.id
        }

        let visibleTitle = normalizedWindowTitle(visibleEntry.windowTitle)
        guard !visibleTitle.isEmpty else {
            return nil
        }

        let exactTitleWindows = sameProcessWindows.filter { window in
            normalizedWindowTitle(window.reference.windowTitle) == visibleTitle
        }
        return nearestPinnedWindowID(
            in: exactTitleWindows,
            to: visibleEntry.asPinnedReference().bounds,
            maxScore: 240
        )
    }

    func bestEffortPinnedWindowIDForVisibleEntry(
        _ visibleEntry: WindowCatalogEntry
    ) -> UUID? {
        if visibleEntry.windowNumber != nil {
            return nil
        }

        let sameProcessWindows = store.allWindows.filter { window in
            window.reference.ownerPID == visibleEntry.ownerPID
        }
        let visibleReference = visibleEntry.asPinnedReference()
        let visibleTitle = normalizedWindowTitle(visibleReference.windowTitle)
        let titledCandidates = sameProcessWindows.filter { window in
            !visibleTitle.isEmpty &&
                normalizedWindowTitle(window.reference.windowTitle) == visibleTitle
        }
        if let matched = nearestPinnedWindowID(
            in: titledCandidates,
            to: visibleReference.bounds,
            maxScore: 120
        ) {
            return matched
        }

        return nearestPinnedWindowID(
            in: sameProcessWindows,
            to: visibleReference.bounds,
            maxScore: 120
        )
    }

    func strictPinnedWindowIDForLiveFocus(
        snapshot focusedWindow: FocusedWindowSnapshot
    ) -> UUID? {
        let sameProcessWindows = store.allWindows.filter { window in
            window.reference.ownerPID == focusedWindow.ownerPID
        }
        guard !sameProcessWindows.isEmpty else {
            return nil
        }

        if let windowNumber = focusedWindow.windowNumber {
            return sameProcessWindows.first { window in
                window.reference.windowNumber == windowNumber
            }?.id
        }

        let focusedTitle = normalizedWindowTitle(focusedWindow.windowTitle)
        guard !focusedTitle.isEmpty,
              let focusedBounds = focusedWindow.bounds else {
            return nil
        }

        let exactTitleMatches = sameProcessWindows.compactMap { window -> (id: UUID, score: Double)? in
            guard normalizedWindowTitle(window.reference.windowTitle) == focusedTitle,
                  let candidateBounds = window.reference.bounds else {
                return nil
            }
            return (
                id: window.id,
                score: boundsDistanceScore(lhs: candidateBounds, rhs: focusedBounds)
            )
        }.sorted { lhs, rhs in
            lhs.score < rhs.score
        }

        guard let best = exactTitleMatches.first,
              best.score <= 240 else {
            return nil
        }
        if exactTitleMatches.count == 1 {
            return best.id
        }

        let runnerUp = exactTitleMatches[1]
        return (runnerUp.score - best.score) >= 120 ? best.id : nil
    }

    func bestEffortPinnedWindowIDForLiveFocus(
        snapshot focusedWindow: FocusedWindowSnapshot
    ) -> UUID? {
        if focusedWindow.windowNumber != nil {
            return nil
        }

        let sameProcessWindows = store.allWindows.filter { window in
            window.reference.ownerPID == focusedWindow.ownerPID
        }
        guard !sameProcessWindows.isEmpty,
              let focusedBounds = focusedWindow.bounds else {
            return nil
        }

        let focusedTitle = normalizedWindowTitle(focusedWindow.windowTitle)
        let scoredWindows = sameProcessWindows.compactMap { window -> (id: UUID, score: Double)? in
            guard let candidateBounds = window.reference.bounds else {
                return nil
            }
            let candidateTitle = normalizedWindowTitle(window.reference.windowTitle)
            if !focusedTitle.isEmpty,
               !candidateTitle.isEmpty,
               candidateTitle != focusedTitle {
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
            return best.score <= 120 ? best.id : nil
        }

        let runnerUp = scoredWindows[1]
        let separation = runnerUp.score - best.score
        if best.score <= 320 && separation >= 120 {
            return best.id
        }

        return nil
    }

    func nearestVisibleEntry(
        in entries: [WindowCatalogEntry],
        to focusedBounds: PinnedWindowBounds
    ) -> WindowCatalogEntry? {
        let scoredEntries = entries.map { entry in
            (
                entry: entry,
                score: boundsDistanceScore(
                    lhs: entry.asPinnedReference().bounds ?? focusedBounds,
                    rhs: focusedBounds
                )
            )
        }.sorted { lhs, rhs in
            lhs.score < rhs.score
        }

        guard let best = scoredEntries.first else {
            return nil
        }
        if best.score <= 40 {
            return best.entry
        }
        if scoredEntries.count == 1 {
            return best.score <= 120 ? best.entry : nil
        }

        let runnerUp = scoredEntries[1]
        return best.score <= 320 && (runnerUp.score - best.score) >= 120
            ? best.entry
            : nil
    }

    func nearestPinnedWindowID(
        in windows: [PinnedWindow],
        to focusedBounds: PinnedWindowBounds?,
        maxScore: Double
    ) -> UUID? {
        guard let focusedBounds else {
            return nil
        }

        let scoredWindows = windows.compactMap { window -> (id: UUID, score: Double)? in
            guard let candidateBounds = window.reference.bounds else {
                return nil
            }
            return (
                id: window.id,
                score: boundsDistanceScore(lhs: candidateBounds, rhs: focusedBounds)
            )
        }.sorted { lhs, rhs in
            lhs.score < rhs.score
        }

        guard let best = scoredWindows.first else {
            return nil
        }
        if scoredWindows.count == 1 {
            return best.score <= maxScore ? best.id : nil
        }

        let runnerUp = scoredWindows[1]
        return best.score <= maxScore && (runnerUp.score - best.score) >= 120
            ? best.id
            : nil
    }

    func boundsDistanceScore(
        lhs: PinnedWindowBounds,
        rhs: PinnedWindowBounds
    ) -> Double {
        abs(lhs.x - rhs.x)
            + abs(lhs.y - rhs.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    func normalizedWindowTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
