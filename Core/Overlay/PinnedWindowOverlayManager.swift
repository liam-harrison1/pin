@preconcurrency import AppKit
import Foundation
import DeskPinsPinned
// swiftlint:disable file_length
private let deskPinsOverlayWindowLevel = NSWindow.Level.statusBar
public enum PinnedWindowOverlayRenderPolicy: Sendable, Equatable {
    case badgeOnly
    case mirrorVisible
    case directInteractionOwner
    case suppressed
}

public struct PinnedWindowOverlayTarget: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var frame: CGRect
    public var isStale: Bool
    public var renderPolicy: PinnedWindowOverlayRenderPolicy
    public var reference: PinnedWindowReference
    /// Opacity applied to the preview overlay window. Range 0.3...1.0.
    public var overlayOpacity: Double
    /// When true the preview overlay ignores mouse events (click-through).
    public var overlayClickThrough: Bool

    public init(
        id: UUID,
        title: String,
        frame: CGRect,
        isStale: Bool,
        renderPolicy: PinnedWindowOverlayRenderPolicy = .mirrorVisible,
        reference: PinnedWindowReference,
        overlayOpacity: Double = 0.92,
        overlayClickThrough: Bool = false
    ) {
        self.id = id
        self.title = title
        self.frame = frame
        self.isStale = isStale
        self.renderPolicy = renderPolicy
        self.reference = reference
        self.overlayOpacity = overlayOpacity
        self.overlayClickThrough = overlayClickThrough
    }
}

public enum PinnedWindowOverlayInteractionEvent: Sendable, Equatable {
    case dragBegan(id: UUID, reference: PinnedWindowReference)
    case dragChanged(
        id: UUID,
        reference: PinnedWindowReference,
        deltaX: Double,
        deltaY: Double
    )
    case dragEnded(id: UUID, reference: PinnedWindowReference)
    case contentInteractionRequested(
        id: UUID,
        reference: PinnedWindowReference,
        screenPoint: PinnedOverlayScreenPoint
    )
    case badgeClicked(id: UUID, reference: PinnedWindowReference)
}

public struct PinnedOverlayScreenPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public typealias PinnedWindowOverlayInteractionHandler = @MainActor (
    PinnedWindowOverlayInteractionEvent
) -> Void
@MainActor
public final class PinnedWindowOverlayManager {
    fileprivate static let primaryPreviewRefreshInterval: TimeInterval = 0.12
    fileprivate static let secondaryPreviewRefreshInterval: TimeInterval = 0.24
    fileprivate static let maxConcurrentCaptures = 1
    fileprivate static let postInteractionCaptureCooldown: TimeInterval = 0.12
    private let permissionChecker: any ScreenRecordingPermissionChecking
    private let previewCapturer: any WindowPreviewCapturing
    private let captureRequestTimeout: TimeInterval
    private var bundlesByID: [UUID: PinnedOverlayBundle] = [:]
    private var captureTasks: [UUID: Task<Void, Never>] = [:]
    private var captureRequestIDs: [UUID: UUID] = [:]
    private var currentTargetOrder: [UUID] = []
    private var interactionHandler: PinnedWindowOverlayInteractionHandler?
    private var interactiveDragTargetIDs: Set<UUID> = []
    private var forceRefreshTargetIDs: Set<UUID> = []
    private var interactionCaptureCooldownByID: [UUID: Date] = [:]
    private var arePreviewCapturesSuppressed = false

    public convenience init(
        permissionChecker: any ScreenRecordingPermissionChecking = LiveScreenRecordingPermissionChecker(),
        previewCapturer: (any WindowPreviewCapturing)? = nil
    ) {
        self.init(
            permissionChecker: permissionChecker,
            previewCapturer: previewCapturer,
            captureRequestTimeout: 1.5
        )
    }

    public init(
        permissionChecker: any ScreenRecordingPermissionChecking,
        previewCapturer: (any WindowPreviewCapturing)?,
        captureRequestTimeout: TimeInterval
    ) {
        self.permissionChecker = permissionChecker
        self.previewCapturer = previewCapturer
            ?? LiveWindowPreviewCapturer(permissionChecker: permissionChecker)
        self.captureRequestTimeout = captureRequestTimeout
    }

    public func currentScreenRecordingStatus() -> ScreenRecordingPermissionStatus {
        permissionChecker.currentStatus()
    }

    public func requestScreenRecordingPermission() -> ScreenRecordingPermissionStatus {
        permissionChecker.requestAccessIfNeeded()
    }

    public func setInteractionHandler(
        _ handler: PinnedWindowOverlayInteractionHandler?
    ) {
        interactionHandler = handler
        for bundle in bundlesByID.values {
            bundle.setInteractionHandler(handler)
        }
    }

    public func beginInteractionDrag(for id: UUID) {
        interactiveDragTargetIDs.insert(id)
        forceRefreshTargetIDs.remove(id)
        interactionCaptureCooldownByID[id] = nil
    }

    public func updateInteractionDrag(
        for id: UUID,
        deltaX: Double,
        deltaY: Double
    ) {
        guard interactiveDragTargetIDs.contains(id),
              let bundle = bundlesByID[id] else {
            return
        }
        bundle.shiftBy(
            deltaX: CGFloat(deltaX),
            deltaY: CGFloat(deltaY)
        )
    }

    public func endInteractionDrag(for id: UUID) {
        guard interactiveDragTargetIDs.remove(id) != nil else {
            return
        }
        forceRefreshTargetIDs.insert(id)
        interactionCaptureCooldownByID[id] = Date.now
            .addingTimeInterval(Self.postInteractionCaptureCooldown)
    }

    public func updateOverlays(with targets: [PinnedWindowOverlayTarget]) {
        let targetIDs = Set(targets.map(\.id))
        let desiredTargetOrder = targets.map(\.id)
        let requiresFrontReorder = desiredTargetOrder != currentTargetOrder
        let topTargetID = desiredTargetOrder.first
        let hasVisiblePreviewTarget = targets.contains { target in
            target.renderPolicy == .mirrorVisible
        }
        let screenRecordingStatus = hasVisiblePreviewTarget
            ? permissionChecker.currentStatus()
            : ScreenRecordingPermissionStatus.denied

        if !hasVisiblePreviewTarget || targets.isEmpty {
            if !arePreviewCapturesSuppressed {
                arePreviewCapturesSuppressed = true
                Task { [previewCapturer] in
                    await previewCapturer.stopAllPreviews()
                }
            }
        } else {
            arePreviewCapturesSuppressed = !hasVisiblePreviewTarget
        }

        for id in bundlesByID.keys where !targetIDs.contains(id) {
            cancelCapture(for: id)
            bundlesByID[id]?.close()
            bundlesByID[id] = nil
            interactiveDragTargetIDs.remove(id)
            forceRefreshTargetIDs.remove(id)
            interactionCaptureCooldownByID[id] = nil
        }

        for target in targets.reversed() {
            let isInteractionActive = interactiveDragTargetIDs.contains(target.id)
            let bundle: PinnedOverlayBundle
            if let existingBundle = bundlesByID[target.id] {
                bundle = existingBundle
                bundle.apply(
                    target: target,
                    updateFrame: !isInteractionActive
                )
                bundle.setInteractionHandler(interactionHandler)
            } else {
                let newBundle = PinnedOverlayBundle(
                    target: target,
                    interactionHandler: interactionHandler
                )
                bundlesByID[target.id] = newBundle
                bundle = newBundle
            }

            switch target.renderPolicy {
            case .badgeOnly:
                cancelCapture(for: target.id)
                bundle.enterBadgeOnlyMode()
                bundle.orderFrontIfNeeded(
                    force: requiresFrontReorder,
                    includePreview: false,
                    includeDragHandle: false,
                    includeBadge: true
                )
                continue
            case .directInteractionOwner:
                cancelCapture(for: target.id)
                bundle.enterDirectInteractionMode()
                bundle.orderFrontIfNeeded(
                    force: requiresFrontReorder,
                    includePreview: false,
                    includeDragHandle: true,
                    includeBadge: false
                )
                continue
            case .suppressed:
                cancelCapture(for: target.id)
                bundle.enterSuppressedMode()
                bundle.orderFrontIfNeeded(
                    force: requiresFrontReorder,
                    includePreview: false,
                    includeDragHandle: false,
                    // Keep a lightweight pin anchor visible so suppressed windows
                    // remain discoverable/clickable without restoring full overlay.
                    includeBadge: true
                )
                continue
            case .mirrorVisible:
                break
            }

            refreshPreviewIfNeeded(
                for: target,
                bundle: bundle,
                screenRecordingStatus: screenRecordingStatus,
                refreshInterval: target.id == topTargetID
                    ? Self.primaryPreviewRefreshInterval
                    : Self.secondaryPreviewRefreshInterval,
                isInteractionActive: isInteractionActive
            )
            bundle.orderFrontIfNeeded(
                force: requiresFrontReorder,
                includePreview: true,
                includeDragHandle: true,
                includeBadge: true
            )
        }

        currentTargetOrder = desiredTargetOrder
    }

    public func removeAllOverlays() {
        let captureIDs = Set(captureTasks.keys).union(captureRequestIDs.keys)
        captureIDs.forEach(cancelCapture(for:))
        bundlesByID.values.forEach { $0.close() }
        bundlesByID.removeAll()
        currentTargetOrder.removeAll()
        interactiveDragTargetIDs.removeAll()
        forceRefreshTargetIDs.removeAll()
        interactionCaptureCooldownByID.removeAll()
        arePreviewCapturesSuppressed = true
        Task { [previewCapturer] in
            await previewCapturer.stopAllPreviews()
        }
    }

    // swiftlint:disable cyclomatic_complexity function_body_length
    private func refreshPreviewIfNeeded(
        for target: PinnedWindowOverlayTarget,
        bundle: PinnedOverlayBundle,
        screenRecordingStatus: ScreenRecordingPermissionStatus,
        refreshInterval: TimeInterval,
        isInteractionActive: Bool
    ) {
        bundle.restoreAfterInteractionSuppression()

        if isInteractionActive {
            cancelCapture(for: target.id)
            bundle.markPreviewAsLive()
            return
        }
        let now = Date.now
        let shouldForceRefresh = forceRefreshTargetIDs.remove(target.id) != nil
        if let cooldownUntil = interactionCaptureCooldownByID[target.id] {
            if now < cooldownUntil {
                bundle.markPreviewAsLive()
                return
            }
            interactionCaptureCooldownByID[target.id] = nil
        }

        switch screenRecordingStatus {
        case .denied:
            cancelCapture(for: target.id)
            if !arePreviewCapturesSuppressed {
                arePreviewCapturesSuppressed = true
                Task { [previewCapturer] in
                    await previewCapturer.stopAllPreviews()
                }
            }
            bundle.showPermissionPlaceholder(title: target.title)
            return
        case .granted:
            break
        }

        if target.isStale {
            cancelCapture(for: target.id)
            bundle.showStalePlaceholder(title: target.title)
            return
        }

        if captureTasks[target.id] != nil {
            if bundle.isPreviewRequestExpired(at: now, timeout: captureRequestTimeout) {
                cancelCapture(for: target.id)
                bundle.showUnavailablePlaceholder(title: target.title)
            } else {
                return
            }
        }

        if captureTasks.count >= Self.maxConcurrentCaptures {
            bundle.markPreviewAsLive()
            return
        }
        guard shouldForceRefresh
                || bundle.shouldRefreshPreview(
                    for: target,
                    at: now,
                    minimumInterval: refreshInterval
                ) else {
            bundle.markPreviewAsLive()
            return
        }
        bundle.markPreviewRequest(for: target, at: now)
        let requestID = UUID()
        captureRequestIDs[target.id] = requestID

        captureTasks[target.id] = Task { [previewCapturer] in
            let image: CGImage?
            do {
                image = try await previewCapturer.capturePreview(for: target.reference)
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        clearCaptureIfCurrent(requestID, for: target.id)
                    }
                    return
                }
                await MainActor.run {
                    guard isCaptureRequestCurrent(requestID, for: target.id) else {
                        return
                    }
                    guard let bundle = bundlesByID[target.id] else {
                        clearCaptureIfCurrent(requestID, for: target.id)
                        return
                    }
                    switch error {
                    case WindowPreviewCaptureError.screenRecordingPermissionDenied:
                        bundle.showPermissionPlaceholder(title: target.title)
                    default:
                        bundle.showUnavailablePlaceholder(title: target.title)
                    }
                    clearCaptureIfCurrent(requestID, for: target.id)
                }
                return
            }
            if Task.isCancelled {
                await MainActor.run {
                    clearCaptureIfCurrent(requestID, for: target.id)
                }
                return
            }
            await MainActor.run {
                guard isCaptureRequestCurrent(requestID, for: target.id) else {
                    return
                }
                guard let bundle = bundlesByID[target.id] else {
                    clearCaptureIfCurrent(requestID, for: target.id)
                    return
                }

                bundle.showPreviewImage(image, title: target.title)
                clearCaptureIfCurrent(requestID, for: target.id)
            }
        }
    }
    // swiftlint:enable cyclomatic_complexity function_body_length

    private func cancelCapture(for id: UUID) {
        captureTasks[id]?.cancel()
        captureTasks[id] = nil
        captureRequestIDs[id] = nil
    }

    private func isCaptureRequestCurrent(_ requestID: UUID, for id: UUID) -> Bool {
        captureRequestIDs[id] == requestID
    }

    private func clearCaptureIfCurrent(_ requestID: UUID, for id: UUID) {
        guard isCaptureRequestCurrent(requestID, for: id) else {
            return
        }

        captureTasks[id] = nil
        captureRequestIDs[id] = nil
    }
}

@MainActor
private final class PinnedOverlayBundle {
    private enum InteractionMode {
        case badgeOnly
        case mirror
        case directOwner
        case suppressed
    }

    private let previewWindow: PinnedPreviewWindow
    private let dragHandleWindow: PinnedDragHandleWindow
    private let badgeWindow: PinnedBadgeWindow
    private var lastPreviewRequestAt: Date?
    private var lastPreviewIdentity: PinnedPreviewIdentity?
    private var interactionMode: InteractionMode = .mirror

    init(
        target: PinnedWindowOverlayTarget,
        interactionHandler: PinnedWindowOverlayInteractionHandler?
    ) {
        previewWindow = PinnedPreviewWindow(target: target)
        dragHandleWindow = PinnedDragHandleWindow(
            target: target,
            interactionHandler: interactionHandler
        )
        badgeWindow = PinnedBadgeWindow(target: target)
        badgeWindow.setInteractionHandler(interactionHandler)
        previewWindow.addChildWindow(badgeWindow, ordered: .above)
        previewWindow.addChildWindow(dragHandleWindow, ordered: .above)
        apply(target: target)
    }

    func apply(
        target: PinnedWindowOverlayTarget,
        updateFrame: Bool = true
    ) {
        previewWindow.apply(
            target: target,
            updateFrame: updateFrame
        )
        dragHandleWindow.apply(
            target: target,
            updateFrame: updateFrame
        )
        badgeWindow.apply(
            target: target,
            updateFrame: updateFrame
        )
    }

    func orderFrontIfNeeded(
        force: Bool,
        includePreview: Bool,
        includeDragHandle: Bool,
        includeBadge: Bool
    ) {
        let previewVisibilityNeedsUpdate = includePreview
            ? !previewWindow.isVisible
            : previewWindow.isVisible
        let dragHandleVisibilityNeedsUpdate = includeDragHandle
            ? !dragHandleWindow.isVisible
            : dragHandleWindow.isVisible
        let badgeVisibilityNeedsUpdate = includeBadge
            ? !badgeWindow.isVisible
            : badgeWindow.isVisible
        guard force
                || previewVisibilityNeedsUpdate
                || dragHandleVisibilityNeedsUpdate
                || badgeVisibilityNeedsUpdate else {
            return
        }

        if includePreview {
            previewWindow.orderFrontRegardless()
        } else {
            previewWindow.orderOut(nil)
        }
        if includeDragHandle {
            dragHandleWindow.orderFrontRegardless()
        } else {
            dragHandleWindow.orderOut(nil)
        }
        if includeBadge {
            badgeWindow.orderFrontRegardless()
        } else {
            badgeWindow.orderOut(nil)
        }
    }

    func close() {
        previewWindow.removeChildWindow(badgeWindow)
        previewWindow.removeChildWindow(dragHandleWindow)
        badgeWindow.close()
        dragHandleWindow.close()
        previewWindow.close()
    }

    func setInteractionHandler(
        _ interactionHandler: PinnedWindowOverlayInteractionHandler?
    ) {
        dragHandleWindow.setInteractionHandler(interactionHandler)
        badgeWindow.setInteractionHandler(interactionHandler)
    }

    func shiftBy(deltaX: CGFloat, deltaY: CGFloat) {
        previewWindow.shiftBy(deltaX: deltaX, deltaY: deltaY)
        dragHandleWindow.shiftBy(deltaX: deltaX, deltaY: deltaY)
        badgeWindow.shiftBy(deltaX: deltaX, deltaY: deltaY)
    }

    func shouldRefreshPreview(
        for target: PinnedWindowOverlayTarget,
        at now: Date,
        minimumInterval: TimeInterval
    ) -> Bool {
        let previewIdentity = PinnedPreviewIdentity(reference: target.reference)
        if lastPreviewIdentity != previewIdentity {
            return true
        }

        guard let lastPreviewRequestAt else {
            return true
        }

        return now.timeIntervalSince(lastPreviewRequestAt) >= minimumInterval
    }

    func markPreviewRequest(
        for target: PinnedWindowOverlayTarget,
        at now: Date
    ) {
        lastPreviewRequestAt = now
        lastPreviewIdentity = PinnedPreviewIdentity(reference: target.reference)
        previewWindow.showLoadingPlaceholder(title: target.title)
    }

    func showPreviewImage(_ image: CGImage?, title: String) {
        previewWindow.showPreviewImage(image, title: title)
    }

    func showPermissionPlaceholder(title: String) {
        previewWindow.showPermissionPlaceholder(title: title)
    }

    func showUnavailablePlaceholder(title: String) {
        previewWindow.showUnavailablePlaceholder(title: title)
    }

    func showStalePlaceholder(title: String) {
        previewWindow.showStalePlaceholder(title: title)
    }

    func markPreviewAsLive() {
        previewWindow.markPreviewAsLive()
    }

    func enterDirectInteractionMode() {
        guard interactionMode != .directOwner else {
            return
        }
        interactionMode = .directOwner
        previewWindow.orderOut(nil)
        dragHandleWindow.setDirectInteractionMode(true)
    }

    func enterBadgeOnlyMode() {
        guard interactionMode != .badgeOnly else {
            return
        }
        interactionMode = .badgeOnly
        previewWindow.orderOut(nil)
        dragHandleWindow.orderOut(nil)
        dragHandleWindow.setDirectInteractionMode(false)
    }

    func enterSuppressedMode() {
        guard interactionMode != .suppressed else {
            return
        }
        interactionMode = .suppressed
        previewWindow.orderOut(nil)
        dragHandleWindow.orderOut(nil)
        dragHandleWindow.setDirectInteractionMode(false)
    }

    func restoreAfterInteractionSuppression() {
        guard interactionMode != .mirror else {
            return
        }
        interactionMode = .mirror
        dragHandleWindow.setDirectInteractionMode(false)
    }

    func isPreviewRequestExpired(at now: Date, timeout: TimeInterval) -> Bool {
        guard let lastPreviewRequestAt else {
            return false
        }

        return now.timeIntervalSince(lastPreviewRequestAt) >= timeout
    }
}

private struct PinnedPreviewIdentity: Equatable {
    var ownerPID: Int32
    var windowNumber: Int?
    var windowTitle: String

    init(reference: PinnedWindowReference) {
        ownerPID = reference.ownerPID
        windowNumber = reference.windowNumber
        windowTitle = reference.windowTitle
    }
}

@MainActor
private final class PinnedPreviewWindow: NSPanel {
    private let previewView = PinnedPreviewView(frame: .zero)

    init(target: PinnedWindowOverlayTarget) {
        super.init(
            contentRect: PinnedOverlayCoordinateSpace.appKitFrame(from: target.frame),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        level = deskPinsOverlayWindowLevel
        contentView = previewView

        apply(target: target)
    }

    func apply(
        target: PinnedWindowOverlayTarget,
        updateFrame: Bool = true
    ) {
        if updateFrame {
            let frame = PinnedOverlayCoordinateSpace.appKitFrame(from: target.frame)
            if !framesApproximatelyEqual(frame, self.frame) {
                setFrame(frame, display: false)
            }
        }
        alphaValue = CGFloat(target.overlayOpacity)
        ignoresMouseEvents = target.overlayClickThrough
        previewView.apply(target: target)
    }

    func shiftBy(deltaX: CGFloat, deltaY: CGFloat) {
        setFrame(frame.offsetBy(dx: deltaX, dy: deltaY), display: false)
    }

    func showPreviewImage(_ image: CGImage?, title: String) {
        previewView.showPreviewImage(image, title: title)
    }

    func showLoadingPlaceholder(title: String) {
        previewView.showLoadingPlaceholder(title: title)
    }

    func showPermissionPlaceholder(title: String) {
        previewView.showPermissionPlaceholder(title: title)
    }

    func showUnavailablePlaceholder(title: String) {
        previewView.showUnavailablePlaceholder(title: title)
    }

    func showStalePlaceholder(title: String) {
        previewView.showStalePlaceholder(title: title)
    }

    func markPreviewAsLive() {
        previewView.markPreviewAsLive()
    }
}

@MainActor
private final class PinnedDragHandleWindow: NSPanel {
    private let dragHandleView = PinnedDragHandleView(frame: .zero)
    private var currentTarget: PinnedWindowOverlayTarget?
    private var isInDirectInteractionMode = false

    init(
        target: PinnedWindowOverlayTarget,
        interactionHandler: PinnedWindowOverlayInteractionHandler?
    ) {
        super.init(
            contentRect: Self.dragHandleFrame(
                for: target,
                directInteractionMode: false
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        level = deskPinsOverlayWindowLevel
        contentView = dragHandleView
        dragHandleView.setInteractionHandler(interactionHandler)
        apply(target: target)
    }
    func apply(
        target: PinnedWindowOverlayTarget,
        updateFrame: Bool = true
    ) {
        currentTarget = target
        if updateFrame {
            let frame = Self.dragHandleFrame(
                for: target,
                directInteractionMode: isInDirectInteractionMode
            )
            if !framesApproximatelyEqual(frame, self.frame) {
                setFrame(frame, display: false)
            }
        }
        dragHandleView.setTarget(target)
    }
    func setInteractionHandler(_ interactionHandler: PinnedWindowOverlayInteractionHandler?) {
        dragHandleView.setInteractionHandler(interactionHandler)
    }
    func setDirectInteractionMode(_ isEnabled: Bool) {
        guard isInDirectInteractionMode != isEnabled else {
            return
        }
        isInDirectInteractionMode = isEnabled
        dragHandleView.setDirectInteractionMode(isEnabled)
        guard let currentTarget else {
            return
        }
        let frame = Self.dragHandleFrame(
            for: currentTarget,
            directInteractionMode: isEnabled
        )
        if !framesApproximatelyEqual(frame, self.frame) {
            setFrame(frame, display: false)
        }
    }
    func shiftBy(deltaX: CGFloat, deltaY: CGFloat) {
        setFrame(frame.offsetBy(dx: deltaX, dy: deltaY), display: false)
    }
    private static func dragHandleFrame(
        for target: PinnedWindowOverlayTarget,
        directInteractionMode: Bool
    ) -> CGRect {
        let fullFrame = PinnedOverlayCoordinateSpace.appKitFrame(from: target.frame).integral
        guard directInteractionMode else {
            return fullFrame
        }

        // Keep direct-mode drag capture area outside the window so title-bar controls remain clickable.
        let railSize = CGSize(width: 60, height: 22)
        let preferredOrigin = CGPoint(
            x: fullFrame.maxX - railSize.width - 6,
            y: fullFrame.maxY + 6
        )
        let preferredFrame = CGRect(
            origin: preferredOrigin,
            size: railSize
        ).integral
        return PinnedOverlayCoordinateSpace.clampToDesktop(preferredFrame)
    }
}

private final class PinnedDragHandleView: NSView {
    private enum PointerZone { case passthrough, edgeGuard, drag }
    private var target: PinnedWindowOverlayTarget?
    private var interactionHandler: PinnedWindowOverlayInteractionHandler?
    private var activePointerZone: PointerZone = .passthrough
    private var lastDragScreenPoint: CGPoint?
    private var isInDirectInteractionMode = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
    func setTarget(_ target: PinnedWindowOverlayTarget) {
        self.target = target
    }
    func setInteractionHandler(_ interactionHandler: PinnedWindowOverlayInteractionHandler?) {
        self.interactionHandler = interactionHandler
    }
    func setDirectInteractionMode(_ isEnabled: Bool) {
        isInDirectInteractionMode = isEnabled
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }
        if isInDirectInteractionMode {
            return self
        }
        return self
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let zone: PointerZone = isInDirectInteractionMode ? .drag : pointerZone(for: point)
        activePointerZone = zone
        guard let target else {
            return
        }
        switch zone {
        case .drag:
            lastDragScreenPoint = screenLocation(for: event)
            interactionHandler?(.dragBegan(id: target.id, reference: target.reference))
        case .passthrough:
            guard !isInDirectInteractionMode else {
                return
            }
            let screenPoint = screenLocation(for: event)
            interactionHandler?(
                .contentInteractionRequested(
                    id: target.id,
                    reference: target.reference,
                    screenPoint: PinnedOverlayScreenPoint(
                        x: Double(screenPoint.x),
                        y: Double(screenPoint.y)
                    )
                )
            )
        case .edgeGuard:
            guard !isInDirectInteractionMode else {
                return
            }
            let screenPoint = screenLocation(for: event)
            interactionHandler?(
                .contentInteractionRequested(
                    id: target.id,
                    reference: target.reference,
                    screenPoint: PinnedOverlayScreenPoint(
                        x: Double(screenPoint.x),
                        y: Double(screenPoint.y)
                    )
                )
            )
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard activePointerZone == .drag,
              let target,
              let previousPoint = lastDragScreenPoint else {
            return
        }
        let currentPoint = screenLocation(for: event)
        let deltaX = Double(currentPoint.x - previousPoint.x)
        let deltaY = Double(currentPoint.y - previousPoint.y)
        lastDragScreenPoint = currentPoint
        if deltaX == 0 && deltaY == 0 {
            return
        }
        interactionHandler?(
            .dragChanged(
                id: target.id,
                reference: target.reference,
                deltaX: deltaX,
                deltaY: deltaY
            )
        )
    }
    override func mouseUp(with event: NSEvent) {
        defer {
            lastDragScreenPoint = nil
            activePointerZone = .passthrough
        }
        guard activePointerZone == .drag, let target else {
            return
        }
        interactionHandler?(.dragEnded(id: target.id, reference: target.reference))
    }
    private func pointerZone(for point: NSPoint) -> PointerZone {
        guard bounds.contains(point) else {
            return .passthrough
        }
        let edgeGuardInset = min(14, max(8, min(bounds.width, bounds.height) * 0.04))
        if !bounds.insetBy(dx: edgeGuardInset, dy: edgeGuardInset).contains(point) {
            return .edgeGuard
        }
        return dragRectWithinBounds().contains(point) ? .drag : .passthrough
    }
    private func dragRectWithinBounds() -> CGRect {
        let edgeGuardInset = min(14, max(8, min(bounds.width, bounds.height) * 0.04))
        let sideInset = min(28, max(12, bounds.width * 0.06))
        let topInset = max(10, edgeGuardInset)
        let dragHeight = min(40, max(24, bounds.height * 0.14))
        let width = max(0, bounds.width - (sideInset * 2))
        let y = max(bounds.minY, bounds.maxY - topInset - dragHeight)
        return CGRect(x: bounds.minX + sideInset, y: y, width: width, height: dragHeight)
    }
    private func screenLocation(for event: NSEvent) -> CGPoint {
        guard let window else {
            return NSEvent.mouseLocation
        }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}

@MainActor
private final class PinnedBadgeWindow: NSPanel {
    private let badgeView = PinnedBadgeView(frame: .zero)

    init(target: PinnedWindowOverlayTarget) {
        super.init(
            contentRect: Self.badgeFrame(for: target),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        level = deskPinsOverlayWindowLevel
        contentView = badgeView
        apply(target: target)
    }
    func apply(
        target: PinnedWindowOverlayTarget,
        updateFrame: Bool = true
    ) {
        if updateFrame {
            let frame = Self.badgeFrame(for: target)
            if !framesApproximatelyEqual(frame, self.frame) {
                setFrame(frame, display: false)
            }
        }
        badgeView.apply(target: target)
    }
    func setInteractionHandler(_ interactionHandler: PinnedWindowOverlayInteractionHandler?) {
        badgeView.setInteractionHandler(interactionHandler)
    }
    func shiftBy(deltaX: CGFloat, deltaY: CGFloat) {
        setFrame(frame.offsetBy(dx: deltaX, dy: deltaY), display: false)
    }
    private static func badgeFrame(for target: PinnedWindowOverlayTarget) -> CGRect {
        let displayFrame = PinnedOverlayCoordinateSpace.appKitFrame(from: target.frame)
        let badgeSize = CGSize(width: 28, height: 28)
        let x = displayFrame.midX - (badgeSize.width / 2)
        let rawY = displayFrame.maxY + 4
        let screenMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? rawY
        let menuBarInset: CGFloat = 24
        let y = min(rawY, screenMaxY - badgeSize.height - menuBarInset)
        return CGRect(origin: CGPoint(x: x, y: y), size: badgeSize)
    }
}

private final class PinnedPreviewView: NSView {
    private let imageView = NSImageView(frame: .zero)
    private let messageField = NSTextField(labelWithString: "")
    private let titleField = NSTextField(labelWithString: "")
    private let materialView = NSVisualEffectView(frame: .zero)
    private var hasPreviewImage = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter

        materialView.state = .active
        materialView.blendingMode = .behindWindow
        materialView.material = .hudWindow

        titleField.font = .systemFont(ofSize: 12, weight: .semibold)
        titleField.textColor = .white
        titleField.maximumNumberOfLines = 1
        titleField.lineBreakMode = .byTruncatingTail
        titleField.alignment = .center

        messageField.font = .systemFont(ofSize: 13, weight: .medium)
        messageField.textColor = .white
        messageField.alignment = .center
        messageField.maximumNumberOfLines = 2
        messageField.lineBreakMode = .byWordWrapping

        addSubview(materialView)
        addSubview(imageView)
        addSubview(titleField)
        addSubview(messageField)

        imageView.isHidden = true
        materialView.isHidden = false
        messageField.isHidden = false
        messageField.stringValue = "Refreshing pinned window preview..."
        alphaValue = 0.88
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        imageView.frame = bounds
        titleField.frame = CGRect(
            x: 12,
            y: bounds.height - 34,
            width: max(0, bounds.width - 24),
            height: 18
        )
        messageField.frame = CGRect(
            x: 24,
            y: max(16, (bounds.height / 2) - 18),
            width: max(0, bounds.width - 48),
            height: 40
        )
    }

    func apply(target: PinnedWindowOverlayTarget) {
        titleField.stringValue = target.title
        needsLayout = true
    }

    func showPreviewImage(_ image: CGImage?, title: String) {
        titleField.stringValue = title
        if let image {
            imageView.image = NSImage(
                cgImage: image,
                size: NSSize(width: image.width, height: image.height)
            )
            hasPreviewImage = true
            imageView.isHidden = false
            materialView.isHidden = true
            messageField.isHidden = true
            alphaValue = 1
        } else {
            hasPreviewImage = false
            showUnavailablePlaceholder(title: title)
        }
    }

    func showLoadingPlaceholder(title: String) {
        titleField.stringValue = title
        guard !hasPreviewImage else {
            return
        }
        imageView.isHidden = true
        materialView.isHidden = false
        messageField.isHidden = false
        messageField.stringValue = "Refreshing pinned window preview..."
        alphaValue = 0.88
    }

    func showPermissionPlaceholder(title: String) {
        titleField.stringValue = title
        hasPreviewImage = false
        imageView.isHidden = true
        materialView.isHidden = false
        messageField.isHidden = false
        messageField.stringValue = "Enable Screen Recording to pin this window above other apps."
        alphaValue = 0.94
    }

    func showUnavailablePlaceholder(title: String) {
        titleField.stringValue = title
        hasPreviewImage = false
        imageView.isHidden = true
        materialView.isHidden = false
        messageField.isHidden = false
        messageField.stringValue = "DeskPins could not refresh this pinned window preview."
        alphaValue = 0.9
    }

    func showStalePlaceholder(title: String) {
        titleField.stringValue = title
        hasPreviewImage = false
        imageView.isHidden = true
        materialView.isHidden = false
        messageField.isHidden = false
        messageField.stringValue = "Pinned window is stale. Refresh to reconnect it."
        alphaValue = 0.82
    }

    func markPreviewAsLive() {
        if !imageView.isHidden {
            materialView.isHidden = true
            messageField.isHidden = true
            alphaValue = 1
        }
    }
}

private final class PinnedBadgeView: NSView {
    private let emojiField = NSTextField(labelWithString: "")
    private var target: PinnedWindowOverlayTarget?
    private var interactionHandler: PinnedWindowOverlayInteractionHandler?
    private var mouseDownLocation: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        emojiField.font = .systemFont(ofSize: 18)
        emojiField.alignment = .center
        emojiField.isBordered = false
        emojiField.drawsBackground = false

        addSubview(emojiField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        emojiField.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = (min(bounds.width, bounds.height) / 2) * 1.18
        let deltaX = point.x - center.x
        let deltaY = point.y - center.y
        let distance = sqrt((deltaX * deltaX) + (deltaY * deltaY))
        return distance <= radius ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
        }
        guard let target else {
            return
        }
        let mouseUpLocation = convert(event.locationInWindow, from: nil)
        if let mouseDownLocation {
            let deltaX = mouseUpLocation.x - mouseDownLocation.x
            let deltaY = mouseUpLocation.y - mouseDownLocation.y
            let distance = sqrt((deltaX * deltaX) + (deltaY * deltaY))
            if distance > 10 {
                return
            }
        }
        interactionHandler?(
            .badgeClicked(
                id: target.id,
                reference: target.reference
            )
        )
    }

    func setInteractionHandler(
        _ interactionHandler: PinnedWindowOverlayInteractionHandler?
    ) {
        self.interactionHandler = interactionHandler
    }

    func apply(target: PinnedWindowOverlayTarget) {
        self.target = target
        let bubbleColor = target.isStale
            ? NSColor.systemOrange.withAlphaComponent(0.95)
            : NSColor.systemYellow.withAlphaComponent(0.95)
        layer?.backgroundColor = bubbleColor.cgColor
        layer?.cornerRadius = bounds.width / 2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = target.isStale ? 1 : 1.5
        emojiField.stringValue = "📌"
        toolTip = target.isStale
            ? "Pinned window may be stale: \(target.title)"
            : "Pinned window: \(target.title)"
        needsLayout = true
    }
}

private func framesApproximatelyEqual(
    _ lhs: CGRect,
    _ rhs: CGRect,
    tolerance: CGFloat = 0.5
) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
    abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
    abs(lhs.size.width - rhs.size.width) <= tolerance &&
    abs(lhs.size.height - rhs.size.height) <= tolerance
}

private enum PinnedOverlayCoordinateSpace {
    static func desktopFrame() -> CGRect {
        NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { partialResult, frame in
                partialResult.union(frame)
            }
    }

    private static func screenContaining(cgFrame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let primaryScreen = screens[0]
        let desktopFrame = desktopFrame()
        let midpoint = CGPoint(
            x: cgFrame.midX,
            y: desktopFrame.maxY - cgFrame.midY
        )
        return screens.first { $0.frame.contains(midpoint) } ?? primaryScreen
    }

    static func clampToDesktop(
        _ frame: CGRect,
        padding: CGFloat = 2
    ) -> CGRect {
        let screenFrame = screenContaining(cgFrame: frame)?.frame
            ?? desktopFrame()
        guard !screenFrame.isNull else {
            return frame
        }

        let minX = screenFrame.minX + padding
        let maxX = screenFrame.maxX - frame.width - padding
        let minY = screenFrame.minY + padding
        let maxY = screenFrame.maxY - frame.height - padding
        let clampedX = min(max(frame.origin.x, minX), maxX)
        let clampedY = min(max(frame.origin.y, minY), maxY)
        return CGRect(
            x: clampedX,
            y: clampedY,
            width: frame.width,
            height: frame.height
        ).integral
    }

    static func appKitFrame(from captureFrame: CGRect) -> CGRect {
        let screenFrame = screenContaining(cgFrame: captureFrame)?.frame
            ?? desktopFrame()

        guard !screenFrame.isNull else {
            return captureFrame
        }

        return CGRect(
            x: captureFrame.origin.x,
            y: screenFrame.maxY - captureFrame.origin.y - captureFrame.height,
            width: captureFrame.width,
            height: captureFrame.height
        )
    }
}
