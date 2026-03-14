@preconcurrency import AppKit
import Foundation
import DeskPinsAccessibility
import DeskPinsAppSupport
import DeskPinsPinned
import DeskPinsPinning
import DeskPinsWindowCatalog

typealias LiveDeskPinsStateController = DeskPinsMenuBarStateController<
    LiveAccessibilityTrustChecker,
    LiveFocusedWindowReader,
    LiveWindowCatalogReader,
    JSONPinnedWindowStorePersistence
>

@main
enum DeskPinsMenuBarApp {
    @MainActor
    private static var appDelegate = DeskPinsMenuBarAppDelegate()

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = appDelegate
        app.run()
    }
}

@MainActor
private final class DeskPinsMenuBarAppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    private let menu = NSMenu()
    private let pinnedCountItem = NSMenuItem(title: "Pinned Windows: 0", action: nil, keyEquivalent: "")
    private let focusItem = NSMenuItem(title: "Focus: Not refreshed", action: nil, keyEquivalent: "")
    private let refreshItem = NSMenuItem(
        title: "Refresh Workspace",
        action: #selector(refreshWorkspace),
        keyEquivalent: "r"
    )
    private let togglePinItem = NSMenuItem(
        title: "Toggle Current Window Pin",
        action: #selector(toggleCurrentWindowPin),
        keyEquivalent: "p"
    )
    private let requestPermissionItem = NSMenuItem(
        title: "Request Accessibility Permission",
        action: #selector(requestAccessibilityPermission),
        keyEquivalent: ""
    )
    private let quitItem = NSMenuItem(
        title: "Quit DeskPins",
        action: #selector(quit),
        keyEquivalent: "q"
    )

    private var stateController: LiveDeskPinsStateController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()

        do {
            stateController = try makeStateController()
            _ = try stateController?.refreshWorkspace()
            updateMenuPresentation()
        } catch {
            updateMenuPresentation()
            presentAlert(
                title: "DeskPins failed to start cleanly",
                message: error.localizedDescription
            )
        }
    }

    private func configureStatusItem() {
        pinnedCountItem.isEnabled = false
        focusItem.isEnabled = false

        refreshItem.target = self
        togglePinItem.target = self
        requestPermissionItem.target = self
        quitItem.target = self

        menu.items = [
            pinnedCountItem,
            focusItem,
            .separator(),
            refreshItem,
            togglePinItem,
            requestPermissionItem,
            .separator(),
            quitItem
        ]

        statusItem.menu = menu
        statusItem.button?.title = "Pins"
        statusItem.button?.toolTip = "DeskPins menu bar app"
    }

    private func makeStateController() throws -> LiveDeskPinsStateController {
        let trustChecker = LiveAccessibilityTrustChecker()
        let focusedReader = LiveFocusedWindowReader(trustChecker: trustChecker)
        let catalogReader = LiveWindowCatalogReader()
        let persistence = JSONPinnedWindowStorePersistence(
            fileURL: try pinnedStoreFileURL()
        )

        return try LiveDeskPinsStateController(
            trustChecker: trustChecker,
            focusedReader: focusedReader,
            catalogReader: catalogReader,
            persistence: persistence
        )
    }

    private func pinnedStoreFileURL() throws -> URL {
        let appSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return appSupportURL
            .appendingPathComponent("DeskPins", isDirectory: true)
            .appendingPathComponent("PinnedWindows.json")
    }

    @objc
    private func refreshWorkspace() {
        guard let stateController else {
            return
        }

        do {
            _ = try stateController.refreshWorkspace()
            updateMenuPresentation()
        } catch {
            presentAlert(
                title: "Refresh failed",
                message: error.localizedDescription
            )
        }
    }

    @objc
    private func toggleCurrentWindowPin() {
        guard let stateController else {
            return
        }

        do {
            let outcome = try stateController.toggleCurrentWindow()
            updateMenuPresentation()

            switch outcome {
            case .pinned(let window):
                presentAlert(
                    title: "Pinned current window",
                    message: window.windowTitle
                )
            case .unpinned(let window):
                presentAlert(
                    title: "Unpinned current window",
                    message: window.windowTitle
                )
            case .requiresAccessibilityPermission:
                presentAlert(
                    title: "Accessibility permission required",
                    message: "Use the menu item to request permission, then retry pinning."
                )
            case .noFocusedWindow:
                presentAlert(
                    title: "No focused window",
                    message: "Bring a normal app window to the front, then retry."
                )
            }
        } catch {
            presentAlert(
                title: "Pin action failed",
                message: error.localizedDescription
            )
        }
    }

    @objc
    private func requestAccessibilityPermission() {
        guard let stateController else {
            return
        }

        let status = stateController.requestAccessibilityPermission()
        updateMenuPresentation()

        switch status {
        case .trusted:
            presentAlert(
                title: "Accessibility enabled",
                message: "DeskPins can now read the focused window and refresh the workspace."
            )
        case .notTrusted:
            presentAlert(
                title: "Grant Accessibility access",
                message: "System Settings should prompt for permission. If it does not, add the app or terminal manually under Privacy & Security > Accessibility."
            )
        }
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateMenuPresentation() {
        let presentation = stateController?.presentation()

        let pinnedCount = presentation?.pinnedCount ?? 0
        pinnedCountItem.title = "Pinned Windows: \(pinnedCount)"

        let focusDescription: String
        if let title = presentation?.focusedWindowTitle,
           !title.isEmpty {
            focusDescription = title
        } else {
            switch presentation?.focusStatus {
            case .requiresAccessibilityPermission:
                focusDescription = "Accessibility permission required"
            case .noFocusedWindow:
                focusDescription = "No focused window"
            case .available:
                focusDescription = "Focused window unavailable"
            case nil:
                focusDescription = "Not refreshed"
            }
        }
        focusItem.title = "Focus: \(focusDescription)"

        let buttonTitle = pinnedCount > 0 ? "Pins \(pinnedCount)" : "Pins"
        statusItem.button?.title = buttonTitle
        statusItem.button?.toolTip = "DeskPins: \(focusDescription)"
    }

    private func presentAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}
