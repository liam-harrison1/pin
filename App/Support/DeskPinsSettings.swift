import Foundation
import DeskPinsPinned

public final class DeskPinsSettings: @unchecked Sendable {
    private let defaults: UserDefaults
    private let orderingModeKey = "com.deskpins.settings.orderingMode"
    private let overlayOpacityKey = "com.deskpins.settings.overlayOpacity"
    private let overlayClickThroughKey = "com.deskpins.settings.overlayClickThrough"

    public static let shared = DeskPinsSettings()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Ordering Mode

    public var orderingMode: PinnedWindowOrderingMode {
        get {
            let raw = defaults.string(forKey: orderingModeKey) ?? "recentInteraction"
            return raw == "recentPin" ? .recentPinFirst : .recentInteractionFirst
        }
        set {
            switch newValue {
            case .recentInteractionFirst:
                defaults.set("recentInteraction", forKey: orderingModeKey)
            case .recentPinFirst:
                defaults.set("recentPin", forKey: orderingModeKey)
            }
        }
    }

    // MARK: - Overlay Opacity

    /// Global overlay opacity in the range 0.3...1.0. Default is 0.92.
    public var overlayOpacity: Double {
        get {
            let stored = defaults.double(forKey: overlayOpacityKey)
            if stored == 0 { return 0.92 }
            return min(1.0, max(0.3, stored))
        }
        set {
            defaults.set(min(1.0, max(0.3, newValue)), forKey: overlayOpacityKey)
        }
    }

    // MARK: - Click-Through

    /// When true, overlay preview windows pass mouse events through to windows below.
    public var overlayClickThrough: Bool {
        get { defaults.bool(forKey: overlayClickThroughKey) }
        set { defaults.set(newValue, forKey: overlayClickThroughKey) }
    }
}
