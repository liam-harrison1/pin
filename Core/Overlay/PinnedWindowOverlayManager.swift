@preconcurrency import AppKit
import Foundation
import DeskPinsPinned

public struct PinnedWindowOverlayTarget: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var frame: CGRect
    public var isStale: Bool
    public var reference: PinnedWindowReference

    public init(
        id: UUID,
        title: String,
        frame: CGRect,
        isStale: Bool,
        reference: PinnedWindowReference
    ) {
        self.id = id
        self.title = title
        self.frame = frame
        self.isStale = isStale
        self.reference = reference
    }
}

@MainActor
public final class PinnedWindowOverlayManager {
    fileprivate static let previewRefreshInterval: TimeInterval = 0.12
    private let permissionChecker: any ScreenRecordingPermissionChecking
    private let previewCapturer: any WindowPreviewCapturing
    private let captureRequestTimeout: TimeInterval
    private var bundlesByID: [UUID: PinnedOverlayBundle] = [:]
    private var captureTasks: [UUID: Task<Void, Never>] = [:]
    private var captureRequestIDs: [UUID: UUID] = [:]
    private var currentTargetOrder: [UUID] = []

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

    public func updateOverlays(with targets: [PinnedWindowOverlayTarget]) {
        let targetIDs = Set(targets.map(\.id))
        let desiredTargetOrder = targets.map(\.id)
        let requiresFrontReorder = desiredTargetOrder != currentTargetOrder

        for id in bundlesByID.keys where !targetIDs.contains(id) {
            cancelCapture(for: id)
            bundlesByID[id]?.close()
            bundlesByID[id] = nil
        }

        for target in targets.reversed() {
            let bundle: PinnedOverlayBundle
            if let existingBundle = bundlesByID[target.id] {
                bundle = existingBundle
                bundle.apply(target: target)
            } else {
                let newBundle = PinnedOverlayBundle(target: target)
                bundlesByID[target.id] = newBundle
                bundle = newBundle
            }

            bundle.orderFrontIfNeeded(force: requiresFrontReorder)
            refreshPreviewIfNeeded(for: target, bundle: bundle)
        }

        currentTargetOrder = desiredTargetOrder
    }

    public func removeAllOverlays() {
        let captureIDs = Set(captureTasks.keys).union(captureRequestIDs.keys)
        captureIDs.forEach(cancelCapture(for:))
        bundlesByID.values.forEach { $0.close() }
        bundlesByID.removeAll()
        currentTargetOrder.removeAll()
    }

    private func refreshPreviewIfNeeded(
        for target: PinnedWindowOverlayTarget,
        bundle: PinnedOverlayBundle
    ) {
        let now = Date.now
        let screenRecordingStatus = permissionChecker.currentStatus()

        switch screenRecordingStatus {
        case .denied:
            cancelCapture(for: target.id)
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

        guard bundle.shouldRefreshPreview(for: target, at: now) else {
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
    private let previewWindow: PinnedPreviewWindow
    private let badgeWindow: PinnedBadgeWindow
    private var lastPreviewRequestAt: Date?
    private var lastPreviewIdentity: PinnedPreviewIdentity?

    init(target: PinnedWindowOverlayTarget) {
        previewWindow = PinnedPreviewWindow(target: target)
        badgeWindow = PinnedBadgeWindow(target: target)
        apply(target: target)
    }

    func apply(target: PinnedWindowOverlayTarget) {
        previewWindow.apply(target: target)
        badgeWindow.apply(target: target)
    }

    func orderFrontIfNeeded(force: Bool) {
        guard force || !previewWindow.isVisible || !badgeWindow.isVisible else {
            return
        }

        previewWindow.orderFrontRegardless()
        badgeWindow.orderFrontRegardless()
    }

    func close() {
        previewWindow.close()
        badgeWindow.close()
    }

    func shouldRefreshPreview(
        for target: PinnedWindowOverlayTarget,
        at now: Date
    ) -> Bool {
        let previewIdentity = PinnedPreviewIdentity(reference: target.reference)
        if lastPreviewIdentity != previewIdentity {
            return true
        }

        guard let lastPreviewRequestAt else {
            return true
        }

        return now.timeIntervalSince(lastPreviewRequestAt) >= PinnedWindowOverlayManager.previewRefreshInterval
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
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        level = .floating
        contentView = previewView

        apply(target: target)
    }

    func apply(target: PinnedWindowOverlayTarget) {
        let frame = PinnedOverlayCoordinateSpace.appKitFrame(from: target.frame)
        if !framesApproximatelyEqual(frame, self.frame) {
            setFrame(frame, display: false)
        }
        previewView.apply(target: target)
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
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        level = .floating
        contentView = badgeView

        apply(target: target)
    }

    func apply(target: PinnedWindowOverlayTarget) {
        let frame = Self.badgeFrame(for: target)
        if !framesApproximatelyEqual(frame, self.frame) {
            setFrame(frame, display: false)
        }
        badgeView.apply(target: target)
    }

    private static func badgeFrame(for target: PinnedWindowOverlayTarget) -> CGRect {
        let displayFrame = PinnedOverlayCoordinateSpace.appKitFrame(from: target.frame)
        let badgeSize = CGSize(width: 28, height: 28)
        let x = displayFrame.midX - (badgeSize.width / 2)
        let y = displayFrame.maxY - badgeSize.height - 8
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

    func apply(target: PinnedWindowOverlayTarget) {
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
    static func appKitFrame(from captureFrame: CGRect) -> CGRect {
        let desktopFrame = NSScreen.screens
            .map(\.frame)
            .reduce(CGRect.null) { partialResult, frame in
                partialResult.union(frame)
            }

        guard !desktopFrame.isNull else {
            return captureFrame
        }

        return CGRect(
            x: captureFrame.origin.x,
            y: desktopFrame.maxY - captureFrame.origin.y - captureFrame.height,
            width: captureFrame.width,
            height: captureFrame.height
        )
    }
}
