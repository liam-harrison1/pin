@preconcurrency import AppKit
import Foundation
import DeskPinsAccessibility
import DeskPinsAppSupport
import DeskPinsHotKey
import DeskPinsOverlay
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
private final class DeskPinsMenuBarAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct OverlayDragSession {
        var pinnedWindowID: UUID
        var reference: PinnedWindowReference
        var moveSession: WindowMoveDragSession?
        var pendingDeltaX: Double
        var pendingDeltaY: Double
        var lastFlushAt: Date

        init(
            pinnedWindowID: UUID,
            reference: PinnedWindowReference,
            moveSession: WindowMoveDragSession?
        ) {
            self.pinnedWindowID = pinnedWindowID
            self.reference = reference
            self.moveSession = moveSession
            pendingDeltaX = 0
            pendingDeltaY = 0
            lastFlushAt = .distantPast
        }
    }

    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.variableLength
    )
    private let menu = NSMenu()
    private let pinnedCountItem = NSMenuItem(title: "Pinned Windows: 0", action: nil, keyEquivalent: "")
    private let focusItem = NSMenuItem(title: "Focus: Not refreshed", action: nil, keyEquivalent: "")
    private let noPinnedWindowsItem = NSMenuItem(
        title: "No pinned windows yet",
        action: nil,
        keyEquivalent: ""
    )
    private let visibleWindowsHeaderItem = NSMenuItem(
        title: "Visible Windows",
        action: nil,
        keyEquivalent: ""
    )
    private let noVisibleWindowsItem = NSMenuItem(
        title: "No visible windows available",
        action: nil,
        keyEquivalent: ""
    )
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
    private let requestScreenRecordingItem = NSMenuItem(
        title: "Request Screen Recording Permission",
        action: #selector(requestScreenRecordingPermission),
        keyEquivalent: ""
    )
    private let quitItem = NSMenuItem(
        title: "Quit DeskPins",
        action: #selector(quit),
        keyEquivalent: "q"
    )

    private let overlayManager = PinnedWindowOverlayManager()
    private var stateController: LiveDeskPinsStateController?
    private var shouldReopenMenuAfterRefresh = false
    private var dynamicPinnedWindowItems: [NSMenuItem] = []
    private var dynamicVisibleWindowItems: [NSMenuItem] = []
    private var refreshTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var hasTornDownUI = false
    private var hotKeyController: DeskPinsGlobalHotKeyController?
    private var windowMover: (any WindowMoving)?
    private var activeOverlayDragSession: OverlayDragSession?
    private var dragFlushWorkItem: DispatchWorkItem?
    private let dragFlushInterval: TimeInterval = 1.0 / 60.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        installTerminationSignalHandlers()

        do {
            stateController = try makeStateController()
            configureOverlayInteractionHandler()
            _ = try stateController?.captureWorkspaceForMenu()
            try installHotKeys()
            updateMenuPresentation()
            startRefreshTimer()
        } catch {
            updateMenuPresentation()
            presentDeskPinsAlert(
                title: "DeskPins failed to start cleanly",
                message: error.localizedDescription
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        endActiveOverlayDragSession(commitPendingDrag: false)
        teardownStatusUI()
        hotKeyController?.unregisterAll()
        hotKeyController = nil
        overlayManager.setInteractionHandler(nil)
        cancelSignalHandlers()
    }

    private func configureStatusItem() {
        pinnedCountItem.isEnabled = false
        focusItem.isEnabled = false
        noPinnedWindowsItem.isEnabled = false
        visibleWindowsHeaderItem.isEnabled = false
        noVisibleWindowsItem.isEnabled = false

        menu.delegate = self
        refreshItem.target = self
        togglePinItem.target = self
        requestPermissionItem.target = self
        requestScreenRecordingItem.target = self
        quitItem.target = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openStatusMenu)

        statusItem.button?.title = "Pins"
        statusItem.button?.toolTip = "DeskPins menu bar app"
        rebuildMenu()
    }

    @objc
    private func toggleVisibleWindow(_ sender: NSMenuItem) {
        guard let stateController,
              let windowID = sender.representedObject as? UUID else {
            return
        }

        do {
            let result = try stateController.toggleVisibleWindow(id: windowID)
            updateMenuPresentation()

            switch result {
            case .pinned(let window):
                presentDeskPinsAlert(
                    title: "Pinned visible window",
                    message: window.windowTitle
                )
            case .unpinned(let window):
                presentDeskPinsAlert(
                    title: "Unpinned visible window",
                    message: window.windowTitle
                )
            case nil:
                presentDeskPinsAlert(
                    title: "Visible window not found",
                    message: "Refresh the workspace and try again."
                )
            }
        } catch {
            presentDeskPinsAlert(
                title: "Visible-window action failed",
                message: error.localizedDescription
            )
        }
    }

    private func makeStateController() throws -> LiveDeskPinsStateController {
        let trustChecker = LiveAccessibilityTrustChecker()
        let focusedReader = LiveFocusedWindowReader(trustChecker: trustChecker)
        let catalogReader = LiveWindowCatalogReader()
        let persistence = JSONPinnedWindowStorePersistence(
            fileURL: try deskPinsPinnedStoreFileURL()
        )
        let windowActivator = LiveWindowActivator(trustChecker: trustChecker)
        windowMover = LiveWindowMover(trustChecker: trustChecker)

        return try LiveDeskPinsStateController(
            trustChecker: trustChecker,
            focusedReader: focusedReader,
            catalogReader: catalogReader,
            persistence: persistence,
            windowActivator: windowActivator
        )
    }

    private func installHotKeys() throws {
        let controller = DeskPinsGlobalHotKeyController { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleHotKey(action)
            }
        }
        try controller.registerDefaultHotKeys()
        hotKeyController = controller
    }

    @objc
    private func openStatusMenu() {
        guard let stateController else {
            presentStatusMenu()
            return
        }

        do {
            _ = try stateController.captureWorkspaceForMenu()
            updateMenuPresentation()
        } catch {
            updateMenuPresentation()
        }

        presentStatusMenu()
    }

    @objc
    private func refreshWorkspace() {
        shouldReopenMenuAfterRefresh = true
        performBackgroundRefresh()
    }

    @objc
    private func toggleCurrentWindowPin() {
        performPinToggle(usePresentedFocus: true, showSuccessAlert: true)
    }

    @objc
    private func revealPinnedWindow(_ sender: NSMenuItem) {
        guard let stateController,
              let windowID = sender.representedObject as? UUID else {
            return
        }

        do {
            let activatedWindow = try stateController.activatePinnedWindow(id: windowID)
            updateMenuPresentation()

            if let activatedWindow {
                presentDeskPinsAlert(
                    title: "Brought pinned window forward",
                    message: activatedWindow.windowTitle
                )
            } else {
                presentDeskPinsAlert(
                    title: "Pinned window not found",
                    message: "Refresh the workspace and try again."
                )
            }
        } catch {
            presentDeskPinsAlert(
                title: "Bring-forward failed",
                message: error.localizedDescription
            )
        }
    }

    @objc
    private func unpinPinnedWindow(_ sender: NSMenuItem) {
        guard let stateController,
              let windowID = sender.representedObject as? UUID else {
            return
        }

        do {
            let removed = try stateController.unpinWindow(id: windowID)
            updateMenuPresentation()

            if let removed {
                presentDeskPinsAlert(
                    title: "Unpinned window",
                    message: removed.windowTitle
                )
            }
        } catch {
            presentDeskPinsAlert(
                title: "Unpin failed",
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
            presentDeskPinsAlert(
                title: "Accessibility enabled",
                message: "DeskPins can now read the focused window and refresh the workspace."
            )
        case .notTrusted:
            presentDeskPinsAlert(
                title: "Grant Accessibility access",
                message: "System Settings should prompt for permission. If it does not, add the app or terminal manually under Privacy & Security > Accessibility."
            )
        }
    }

    @objc
    private func requestScreenRecordingPermission() {
        let status = overlayManager.requestScreenRecordingPermission()

        switch status {
        case .granted:
            presentDeskPinsAlert(
                title: "Screen Recording enabled",
                message: "DeskPins can now render pinned window content previews above other apps."
            )
        case .denied:
            presentDeskPinsAlert(
                title: "Grant Screen Recording access",
                message: "Add the host app under Privacy & Security > Screen Recording, then relaunch DeskPins if needed."
            )
        }
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard shouldReopenMenuAfterRefresh else {
            return
        }

        shouldReopenMenuAfterRefresh = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.openStatusMenu()
        }
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
        rebuildDynamicPinnedWindowItems(using: presentation)
        rebuildDynamicVisibleWindowItems(using: presentation)
        rebuildMenu()
        updateOverlays()
    }

    private func rebuildDynamicPinnedWindowItems(
        using presentation: DeskPinsMenuBarPresentation?
    ) {
        dynamicPinnedWindowItems.removeAll()

        let pinnedWindows = presentation?.pinnedWindows ?? []

        guard !pinnedWindows.isEmpty else {
            return
        }

        dynamicPinnedWindowItems = pinnedWindows.flatMap { pinnedWindow in
            let revealPrefix = pinnedWindow.isInvalidated ? "Reveal stale: " : "Reveal pinned: "
            let revealItem = NSMenuItem(
                title: "\(revealPrefix)\(pinnedWindow.title)",
                action: #selector(revealPinnedWindow(_:)),
                keyEquivalent: ""
            )
            revealItem.target = self
            revealItem.representedObject = pinnedWindow.id

            let unpinPrefix = pinnedWindow.isInvalidated ? "Unpin stale: " : "Unpin: "
            let unpinItem = NSMenuItem(
                title: "\(unpinPrefix)\(pinnedWindow.title)",
                action: #selector(unpinPinnedWindow(_:)),
                keyEquivalent: ""
            )
            unpinItem.target = self
            unpinItem.representedObject = pinnedWindow.id

            return [revealItem, unpinItem]
        }
    }

    private func rebuildDynamicVisibleWindowItems(
        using presentation: DeskPinsMenuBarPresentation?
    ) {
        dynamicVisibleWindowItems.removeAll()

        let visibleWindows = presentation?.visibleWindows ?? []

        guard !visibleWindows.isEmpty else {
            return
        }

        dynamicVisibleWindowItems = visibleWindows.map { window in
            let prefix = window.isPinned ? "Unpin visible: " : "Pin visible: "
            let item = NSMenuItem(
                title: "\(prefix)\(window.title)",
                action: #selector(toggleVisibleWindow(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = window.id
            return item
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.items = [
            pinnedCountItem,
            focusItem
        ]

        if dynamicPinnedWindowItems.isEmpty {
            menu.addItem(noPinnedWindowsItem)
        } else {
            dynamicPinnedWindowItems.forEach(menu.addItem(_:))
        }

        menu.addItem(.separator())
        menu.addItem(visibleWindowsHeaderItem)

        if dynamicVisibleWindowItems.isEmpty {
            menu.addItem(noVisibleWindowsItem)
        } else {
            dynamicVisibleWindowItems.forEach(menu.addItem(_:))
        }

        menu.addItem(.separator())
        menu.addItem(refreshItem)
        menu.addItem(togglePinItem)
        menu.addItem(requestPermissionItem)
        menu.addItem(requestScreenRecordingItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    private func updateOverlays() {
        let targets = stateController?.overlayTargets() ?? []
        overlayManager.updateOverlays(with: targets)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 0.05,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performBackgroundRefresh()
            }
        }
        refreshTimer?.tolerance = 0.01
    }

    private func performBackgroundRefresh() {
        guard let stateController else {
            return
        }

        do {
            _ = try stateController.refreshWorkspace()
            updateMenuPresentation()
        } catch {
            updateMenuPresentation()
        }
    }

    private func installTerminationSignalHandlers() {
        let signals = [SIGINT, SIGTERM, SIGHUP, SIGTSTP]

        signalSources = signals.map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.handleTerminationSignal()
            }
            source.resume()
            return source
        }
    }
}

private extension DeskPinsMenuBarAppDelegate {
    func configureOverlayInteractionHandler() {
        overlayManager.setInteractionHandler { [weak self] event in
            self?.handleOverlayInteraction(event)
        }
    }

    func handleOverlayInteraction(_ event: PinnedWindowOverlayInteractionEvent) {
        switch event {
        case .dragBegan(let id, let reference):
            guard let stateController else {
                return
            }

            do {
                _ = try stateController.activatePinnedWindow(id: id)
                updateMenuPresentation()
            } catch {}

            beginOverlayDragSession(
                pinnedWindowID: id,
                reference: reference
            )
        case .dragChanged(let id, _, let deltaX, let deltaY):
            guard var dragSession = activeOverlayDragSession,
                  dragSession.pinnedWindowID == id else {
                return
            }

            dragSession.pendingDeltaX += deltaX
            dragSession.pendingDeltaY += deltaY
            activeOverlayDragSession = dragSession
            schedulePendingDragFlush()
        case .dragEnded(let id, _):
            flushPendingDragDeltas(force: true)
            overlayManager.endInteractionDrag(for: id)
            endActiveOverlayDragSession(commitPendingDrag: false)
            performBackgroundRefresh()
        }
    }

    func beginOverlayDragSession(
        pinnedWindowID: UUID,
        reference: PinnedWindowReference
    ) {
        endActiveOverlayDragSession(commitPendingDrag: false)
        overlayManager.beginInteractionDrag(for: pinnedWindowID)

        let moveSession: WindowMoveDragSession?
        if let windowMover {
            moveSession = try? windowMover.beginDragSession(for: reference)
        } else {
            moveSession = nil
        }
        activeOverlayDragSession = OverlayDragSession(
            pinnedWindowID: pinnedWindowID,
            reference: reference,
            moveSession: moveSession
        )
    }

    func schedulePendingDragFlush() {
        guard dragFlushWorkItem == nil,
              let dragSession = activeOverlayDragSession else {
            return
        }

        let elapsed = Date.now.timeIntervalSince(dragSession.lastFlushAt)
        let delay = max(0, dragFlushInterval - elapsed)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.dragFlushWorkItem = nil
            self.flushPendingDragDeltas(force: true)

            if let pendingDragSession = self.activeOverlayDragSession,
               pendingDragSession.pendingDeltaX != 0
                || pendingDragSession.pendingDeltaY != 0 {
                self.schedulePendingDragFlush()
            }
        }

        dragFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    func flushPendingDragDeltas(force: Bool) {
        guard var dragSession = activeOverlayDragSession else {
            return
        }

        if !force {
            let elapsed = Date.now.timeIntervalSince(dragSession.lastFlushAt)
            if elapsed < dragFlushInterval {
                schedulePendingDragFlush()
                return
            }
        }

        let deltaX = dragSession.pendingDeltaX
        let deltaY = dragSession.pendingDeltaY
        guard deltaX != 0 || deltaY != 0 else {
            return
        }

        dragSession.pendingDeltaX = 0
        dragSession.pendingDeltaY = 0
        dragSession.lastFlushAt = .now
        activeOverlayDragSession = dragSession

        overlayManager.updateInteractionDrag(
            for: dragSession.pinnedWindowID,
            deltaX: deltaX,
            deltaY: deltaY
        )

        guard let windowMover else {
            return
        }

        do {
            if let moveSession = dragSession.moveSession {
                try windowMover.moveWindow(
                    in: moveSession,
                    deltaX: deltaX,
                    deltaY: -deltaY
                )
            } else {
                try windowMover.moveWindow(
                    reference: dragSession.reference,
                    deltaX: deltaX,
                    deltaY: -deltaY
                )
            }
        } catch {
            if dragSession.moveSession != nil {
                do {
                    try windowMover.moveWindow(
                        reference: dragSession.reference,
                        deltaX: deltaX,
                        deltaY: -deltaY
                    )
                } catch {}
            }
        }
    }

    func endActiveOverlayDragSession(commitPendingDrag: Bool) {
        if commitPendingDrag {
            flushPendingDragDeltas(force: true)
        }

        dragFlushWorkItem?.cancel()
        dragFlushWorkItem = nil

        guard let dragSession = activeOverlayDragSession else {
            return
        }

        if let moveSession = dragSession.moveSession {
            windowMover?.endDragSession(moveSession)
        }

        overlayManager.endInteractionDrag(for: dragSession.pinnedWindowID)
        activeOverlayDragSession = nil
    }

    func handleHotKey(_ action: DeskPinsHotKeyAction) {
        switch action {
        case .toggleCurrentWindowPin:
            performPinToggle(usePresentedFocus: false, showSuccessAlert: false)
        }
    }

    func performPinToggle(
        usePresentedFocus: Bool,
        showSuccessAlert: Bool
    ) {
        guard let stateController else {
            return
        }

        do {
            let outcome = usePresentedFocus
                ? try stateController.togglePresentedFocusedWindow()
                : try stateController.toggleCurrentWindow()
            updateMenuPresentation()
            presentPinOutcome(
                outcome,
                showSuccessAlert: showSuccessAlert
            )
        } catch {
            presentDeskPinsAlert(
                title: "Pin action failed",
                message: error.localizedDescription
            )
        }
    }

    func presentPinOutcome(
        _ outcome: PinCurrentWindowActionOutcome,
        showSuccessAlert: Bool
    ) {
        switch outcome {
        case .pinned(let window):
            guard showSuccessAlert else {
                return
            }
            presentDeskPinsAlert(
                title: "Pinned current window",
                message: window.windowTitle
            )
        case .unpinned(let window):
            guard showSuccessAlert else {
                return
            }
            presentDeskPinsAlert(
                title: "Unpinned current window",
                message: window.windowTitle
            )
        case .requiresAccessibilityPermission:
            presentDeskPinsAlert(
                title: "Accessibility permission required",
                message: "Use the menu item to request permission, then retry pinning."
            )
        case .noFocusedWindow:
            presentDeskPinsAlert(
                title: "No focused window",
                message: "Bring a normal app window to the front, then retry."
            )
        }
    }

    func presentStatusMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func handleTerminationSignal() {
        teardownStatusUI()
        cancelSignalHandlers()
        NSApplication.shared.terminate(nil)
    }

    func teardownStatusUI() {
        guard !hasTornDownUI else {
            return
        }

        hasTornDownUI = true
        refreshTimer?.invalidate()
        refreshTimer = nil
        menu.cancelTracking()
        statusItem.menu = nil
        overlayManager.removeAllOverlays()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func cancelSignalHandlers() {
        signalSources.forEach { $0.cancel() }
        signalSources.removeAll()
    }
}

private func deskPinsPinnedStoreFileURL() throws -> URL {
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

@MainActor
private func presentDeskPinsAlert(title: String, message: String) {
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .informational
    alert.runModal()
}
