@preconcurrency import AppKit
@preconcurrency import CoreGraphics
@preconcurrency import CoreImage
@preconcurrency import CoreMedia
@preconcurrency import CoreVideo
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
    func stopAllPreviews() async
}

public extension WindowPreviewCapturing {
    func stopAllPreviews() async {}
}

public struct NoopWindowPreviewCapturer: WindowPreviewCapturing {
    public init() {}

    public func capturePreview(for reference: PinnedWindowReference) async throws -> CGImage? {
        nil
    }

    public func stopAllPreviews() async {}
}

public struct LiveWindowPreviewCapturer: WindowPreviewCapturing {
    private let permissionChecker: any ScreenRecordingPermissionChecking
    private let shareableContentCache: ShareableContentSnapshotCache
    private let streamRegistry: StreamPreviewSessionRegistry
    private let streamWarmupTimeout: TimeInterval
    private let preferredFrameRate: Int32
    private let preferredQueueDepth: Int

    public init(
        permissionChecker: any ScreenRecordingPermissionChecking = LiveScreenRecordingPermissionChecker(),
        shareableContentCacheTTL: TimeInterval = 0.22,
        streamIdleTTL: TimeInterval = 1.8,
        streamWarmupTimeout: TimeInterval = 0.2,
        preferredFrameRate: Int32 = 15,
        preferredQueueDepth: Int = 3
    ) {
        self.permissionChecker = permissionChecker
        shareableContentCache = ShareableContentSnapshotCache(
            ttl: shareableContentCacheTTL
        )
        streamRegistry = StreamPreviewSessionRegistry(
            idleTTL: streamIdleTTL
        )
        self.streamWarmupTimeout = streamWarmupTimeout
        self.preferredFrameRate = preferredFrameRate
        self.preferredQueueDepth = preferredQueueDepth
    }

    public func capturePreview(for reference: PinnedWindowReference) async throws -> CGImage? {
        guard permissionChecker.currentStatus() == .granted else {
            await streamRegistry.stopAll()
            throw WindowPreviewCaptureError.screenRecordingPermissionDenied
        }

        let windows = try await loadShareableWindows()
        guard let window = matchingWindow(
            for: reference,
            in: windows
        ) else {
            throw WindowPreviewCaptureError.noMatchingWindow
        }

        let captureSize = capturePixelSize(for: window.frame)
        do {
            return try await streamRegistry.previewImage(
                for: window,
                captureSize: captureSize,
                warmupTimeout: streamWarmupTimeout,
                preferredFrameRate: preferredFrameRate,
                queueDepth: preferredQueueDepth
            )
        } catch let error as WindowPreviewCaptureError {
            throw error
        } catch {
            throw WindowPreviewCaptureError.captureFailed(error.localizedDescription)
        }
    }

    public func stopAllPreviews() async {
        await streamRegistry.stopAll()
    }

    private func loadShareableWindows() async throws -> [SCWindow] {
        let now = Date.now
        if let cachedWindows = shareableContentCache.windowsIfFresh(at: now) {
            return cachedWindows
        }

        let shareableContent = try await loadShareableContent()
        let windows = shareableContent.windows
        shareableContentCache.cache(windows, at: now)
        return windows
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

    private func capturePixelSize(for frame: CGRect) -> CaptureSize {
        let scale = backingScaleFactor(for: frame)
        let width = max(1, Int((frame.width * scale).rounded(.up)))
        let height = max(1, Int((frame.height * scale).rounded(.up)))
        return CaptureSize(width: width, height: height)
    }

    private func backingScaleFactor(for frame: CGRect) -> Double {
        let midpoint = CGPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) {
            return screen.backingScaleFactor
        }

        if let intersectingScreen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            return intersectingScreen.backingScaleFactor
        }

        return Double(NSScreen.main?.backingScaleFactor ?? 2)
    }
}

private struct CaptureSize: Equatable {
    let width: Int
    let height: Int
}

private final class ShareableContentSnapshotCache: @unchecked Sendable {
    private let ttl: TimeInterval
    private let lock = NSLock()
    private var cachedWindows: [SCWindow]?
    private var cachedAt: Date?

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func windowsIfFresh(at now: Date) -> [SCWindow]? {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard let cachedAt,
              now.timeIntervalSince(cachedAt) < ttl else {
            return nil
        }

        return cachedWindows
    }

    func cache(_ windows: [SCWindow], at now: Date) {
        lock.lock()
        defer {
            lock.unlock()
        }

        cachedWindows = windows
        cachedAt = now
    }
}

private final class StreamPreviewSessionRegistry: @unchecked Sendable {
    private struct SessionRecord {
        var session: StreamPreviewSession
        var captureSize: CaptureSize
        var lastTouchedAt: Date
    }

    private let idleTTL: TimeInterval
    private let lock = NSLock()
    private var sessionsByWindowID: [CGWindowID: SessionRecord] = [:]

    init(idleTTL: TimeInterval) {
        self.idleTTL = idleTTL
    }

    func previewImage(
        for window: SCWindow,
        captureSize: CaptureSize,
        warmupTimeout: TimeInterval,
        preferredFrameRate: Int32,
        queueDepth: Int
    ) async throws -> CGImage? {
        let now = Date.now
        let expiredSessions = takeExpiredSessions(at: now)
        await stopSessions(expiredSessions)

        let windowID = window.windowID
        if let existingSession = touchIfCompatible(
            windowID: windowID,
            captureSize: captureSize,
            at: now
        ) {
            if let image = existingSession.latestImage() {
                return image
            }

            return await existingSession.waitForFrame(timeout: warmupTimeout)
        }

        if let staleSession = removeSession(windowID: windowID) {
            try? await staleSession.stop()
        }

        let newSession = try await StreamPreviewSession(
            window: window,
            captureSize: captureSize,
            preferredFrameRate: preferredFrameRate,
            queueDepth: queueDepth
        )
        let activeSession = installOrReuse(
            newSession,
            windowID: windowID,
            captureSize: captureSize,
            at: now
        )
        if activeSession !== newSession {
            try? await newSession.stop()
        }

        if let image = activeSession.latestImage() {
            return image
        }

        return await activeSession.waitForFrame(timeout: warmupTimeout)
    }

    func stopAll() async {
        let sessions = removeAllSessions()
        await stopSessions(sessions)
    }

    private func touchIfCompatible(
        windowID: CGWindowID,
        captureSize: CaptureSize,
        at now: Date
    ) -> StreamPreviewSession? {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard var record = sessionsByWindowID[windowID],
              record.captureSize == captureSize else {
            return nil
        }

        record.lastTouchedAt = now
        sessionsByWindowID[windowID] = record
        return record.session
    }

    private func installOrReuse(
        _ session: StreamPreviewSession,
        windowID: CGWindowID,
        captureSize: CaptureSize,
        at now: Date
    ) -> StreamPreviewSession {
        lock.lock()
        defer {
            lock.unlock()
        }

        if let existingRecord = sessionsByWindowID[windowID],
           existingRecord.captureSize == captureSize {
            var touchedRecord = existingRecord
            touchedRecord.lastTouchedAt = now
            sessionsByWindowID[windowID] = touchedRecord
            return existingRecord.session
        }

        sessionsByWindowID[windowID] = SessionRecord(
            session: session,
            captureSize: captureSize,
            lastTouchedAt: now
        )
        return session
    }

    private func removeSession(windowID: CGWindowID) -> StreamPreviewSession? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return sessionsByWindowID.removeValue(forKey: windowID)?.session
    }

    private func removeAllSessions() -> [StreamPreviewSession] {
        lock.lock()
        defer {
            lock.unlock()
        }

        let sessions = sessionsByWindowID.values.map(\.session)
        sessionsByWindowID.removeAll()
        return sessions
    }

    private func takeExpiredSessions(at now: Date) -> [StreamPreviewSession] {
        lock.lock()
        defer {
            lock.unlock()
        }

        var expiredWindowIDs: [CGWindowID] = []
        for (windowID, record) in sessionsByWindowID where now.timeIntervalSince(record.lastTouchedAt) >= idleTTL {
            expiredWindowIDs.append(windowID)
        }

        var sessions: [StreamPreviewSession] = []
        for windowID in expiredWindowIDs {
            if let record = sessionsByWindowID.removeValue(forKey: windowID) {
                sessions.append(record.session)
            }
        }

        return sessions
    }

    private func stopSessions(_ sessions: [StreamPreviewSession]) async {
        for session in sessions {
            try? await session.stop()
        }
    }
}

private final class StreamPreviewSession: @unchecked Sendable {
    private let stream: SCStream
    private let outputSink: StreamPreviewOutputSink
    private let outputQueue: DispatchQueue
    private let frameStore = LatestPreviewFrameStore()
    private let stopLock = NSLock()
    private var didStop = false

    init(
        window: SCWindow,
        captureSize: CaptureSize,
        preferredFrameRate: Int32,
        queueDepth: Int
    ) async throws {
        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = captureSize.width
        configuration.height = captureSize.height
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.queueDepth = max(3, min(8, queueDepth))
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: max(1, preferredFrameRate)
        )

        outputSink = StreamPreviewOutputSink(frameStore: frameStore)
        outputQueue = DispatchQueue(
            label: "DeskPins.StreamPreview.\(window.windowID)",
            qos: .utility
        )
        stream = SCStream(
            filter: contentFilter,
            configuration: configuration,
            delegate: nil
        )

        do {
            try stream.addStreamOutput(
                outputSink,
                type: .screen,
                sampleHandlerQueue: outputQueue
            )
            try await stream.startCapture()
        } catch {
            throw WindowPreviewCaptureError.captureFailed(error.localizedDescription)
        }
    }

    func latestImage() -> CGImage? {
        frameStore.latestImage()
    }

    func waitForFrame(timeout: TimeInterval) async -> CGImage? {
        if let image = frameStore.latestImage() {
            return image
        }

        let timeoutNanoseconds = max(0, UInt64(timeout * 1_000_000_000))
        let start = DispatchTime.now().uptimeNanoseconds

        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: 16_000_000)
            if let image = frameStore.latestImage() {
                return image
            }
        }

        return frameStore.latestImage()
    }

    func stop() async throws {
        guard markStoppingIfNeeded() else {
            return
        }

        do {
            try await stream.stopCapture()
        } catch {
            throw WindowPreviewCaptureError.captureFailed(error.localizedDescription)
        }
    }

    private func markStoppingIfNeeded() -> Bool {
        stopLock.lock()
        defer {
            stopLock.unlock()
        }

        guard !didStop else {
            return false
        }

        didStop = true
        return true
    }
}

private final class StreamPreviewOutputSink: NSObject, SCStreamOutput {
    private let frameStore: LatestPreviewFrameStore
    private let ciContext = CIContext()

    init(frameStore: LatestPreviewFrameStore) {
        self.frameStore = frameStore
        super.init()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              sampleBufferHasCompleteFrame(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)

        guard let cgImage = ciContext.createCGImage(ciImage, from: imageBounds) else {
            return
        }

        frameStore.store(image: cgImage)
    }

    private func sampleBufferHasCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw) else {
            return true
        }

        return status == .complete
    }
}

private final class LatestPreviewFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var image: CGImage?

    func latestImage() -> CGImage? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return image
    }

    func store(image: CGImage) {
        lock.lock()
        defer {
            lock.unlock()
        }

        self.image = image
    }
}
