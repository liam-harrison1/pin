@preconcurrency import ApplicationServices
import Foundation

public enum AccessibilityTrustStatus: String, Sendable, Equatable, Codable {
    case trusted
    case notTrusted
}

public protocol AccessibilityTrustChecking: Sendable {
    func currentStatus() -> AccessibilityTrustStatus
    func requestAccessIfNeeded() -> AccessibilityTrustStatus
}

public struct LiveAccessibilityTrustChecker: AccessibilityTrustChecking {
    public init() {}

    public func currentStatus() -> AccessibilityTrustStatus {
        AXIsProcessTrusted() ? .trusted : .notTrusted
    }

    public func requestAccessIfNeeded() -> AccessibilityTrustStatus {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .trusted : .notTrusted
    }
}

public struct StaticAccessibilityTrustChecker: AccessibilityTrustChecking {
    public let status: AccessibilityTrustStatus

    public init(status: AccessibilityTrustStatus) {
        self.status = status
    }

    public func currentStatus() -> AccessibilityTrustStatus {
        status
    }

    public func requestAccessIfNeeded() -> AccessibilityTrustStatus {
        status
    }
}
