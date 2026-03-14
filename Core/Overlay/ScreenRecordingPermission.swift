@preconcurrency import CoreGraphics
import Foundation

public enum ScreenRecordingPermissionStatus: Sendable, Equatable {
    case granted
    case denied
}

public protocol ScreenRecordingPermissionChecking: Sendable {
    func currentStatus() -> ScreenRecordingPermissionStatus
    func requestAccessIfNeeded() -> ScreenRecordingPermissionStatus
}

public struct LiveScreenRecordingPermissionChecker: ScreenRecordingPermissionChecking {
    public init() {}

    public func currentStatus() -> ScreenRecordingPermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    public func requestAccessIfNeeded() -> ScreenRecordingPermissionStatus {
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }

        _ = CGRequestScreenCaptureAccess()
        return CGPreflightScreenCaptureAccess() ? .granted : .denied
    }
}

public struct StaticScreenRecordingPermissionChecker: ScreenRecordingPermissionChecking {
    public var status: ScreenRecordingPermissionStatus

    public init(status: ScreenRecordingPermissionStatus) {
        self.status = status
    }

    public func currentStatus() -> ScreenRecordingPermissionStatus {
        status
    }

    public func requestAccessIfNeeded() -> ScreenRecordingPermissionStatus {
        status
    }
}
