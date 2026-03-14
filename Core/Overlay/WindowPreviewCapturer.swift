@preconcurrency import CoreGraphics
@preconcurrency import ScreenCaptureKit
import Foundation
import DeskPinsPinned

public enum WindowPreviewCaptureError: Error, Sendable, Equatable, CustomStringConvertible {
    case screenRecordingPermissionDenied
    case noMatchingWindow
    case captureFailed(String)

    public var description: String {
        switch self {
        case .screenRecordingPermissionDenied:
            return "Screen Recording permission is required to render pinned content previews."
        case .noMatchingWindow:
            return "DeskPins could not find a matching window to capture."
        case .captureFailed(let detail):
            return "DeskPins could not capture the pinned window preview: \(detail)"
        }
    }
}

public protocol WindowPreviewCapturing: Sendable {
    func capturePreview(for reference: PinnedWindowReference) async throws -> CGImage?
}

public struct NoopWindowPreviewCapturer: WindowPreviewCapturing {
    public init() {}

    public func capturePreview(for reference: PinnedWindowReference) async throws -> CGImage? {
        nil
    }
}

public struct LiveWindowPreviewCapturer: WindowPreviewCapturing {
    private let permissionChecker: any ScreenRecordingPermissionChecking

    public init(
        permissionChecker: any ScreenRecordingPermissionChecking = LiveScreenRecordingPermissionChecker()
    ) {
        self.permissionChecker = permissionChecker
    }

    public func capturePreview(for reference: PinnedWindowReference) async throws -> CGImage? {
        guard permissionChecker.currentStatus() == .granted else {
            throw WindowPreviewCaptureError.screenRecordingPermissionDenied
        }

        let shareableContent = try await loadShareableContent()
        guard let window = matchingWindow(
            for: reference,
            in: shareableContent.windows
        ) else {
            throw WindowPreviewCaptureError.noMatchingWindow
        }

        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width))
        configuration.height = max(1, Int(window.frame.height))
        configuration.scalesToFit = true

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: configuration
            )
        } catch {
            throw WindowPreviewCaptureError.captureFailed(error.localizedDescription)
        }
    }

    private func loadShareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
        } catch {
            throw WindowPreviewCaptureError.captureFailed(error.localizedDescription)
        }
    }

    private func matchingWindow(
        for reference: PinnedWindowReference,
        in windows: [SCWindow]
    ) -> SCWindow? {
        if let windowNumber = reference.windowNumber,
           let exactWindow = windows.first(where: { Int($0.windowID) == windowNumber }) {
            return exactWindow
        }

        let title = reference.windowTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return windows.max { lhs, rhs in
            matchScore(for: lhs, reference: reference, normalizedTitle: title) <
                matchScore(for: rhs, reference: reference, normalizedTitle: title)
        }.flatMap { bestWindow in
            let score = matchScore(for: bestWindow, reference: reference, normalizedTitle: title)
            return score > 0 ? bestWindow : nil
        }
    }

    private func matchScore(
        for window: SCWindow,
        reference: PinnedWindowReference,
        normalizedTitle: String
    ) -> Int {
        var score = 0

        if window.owningApplication?.processID == reference.ownerPID {
            score += 50
        }

        let candidateTitle = (window.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTitle.isEmpty && candidateTitle == normalizedTitle {
            score += 100
        }

        if let bounds = reference.bounds,
           approximatelyMatches(bounds, frame: window.frame) {
            score += 25
        }

        return score
    }

    private func approximatelyMatches(
        _ bounds: PinnedWindowBounds,
        frame: CGRect
    ) -> Bool {
        abs(bounds.x - frame.origin.x) <= 16 &&
        abs(bounds.y - frame.origin.y) <= 16 &&
        abs(bounds.width - frame.width) <= 24 &&
        abs(bounds.height - frame.height) <= 24
    }
}
