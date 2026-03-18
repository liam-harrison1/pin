import AppKit
import Foundation
import DeskPinsPinned

/// A lightweight settings panel that lets the user configure ordering mode,
/// overlay opacity, and overlay click-through behaviour.
@MainActor
public final class DeskPinsSettingsPanelController: NSObject, NSWindowDelegate {
    private let settings: DeskPinsSettings
    private let onDismiss: () -> Void
    private var panel: NSPanel?

    public init(settings: DeskPinsSettings, onDismiss: @escaping () -> Void) {
        self.settings = settings
        self.onDismiss = onDismiss
    }

    public func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = buildPanel()
        self.panel = panel
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        panel = nil
        onDismiss()
    }

    // MARK: - Build

    private func buildPanel() -> NSPanel {
        let contentView = buildContentView()
        let panelSize = contentView.fittingSize
        let panelRect = CGRect(
            x: 0, y: 0,
            width: max(340, panelSize.width),
            height: max(panelSize.height, 180)
        )

        let newPanel = NSPanel(
            contentRect: panelRect,
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "DeskPins Settings"
        newPanel.isFloatingPanel = true
        newPanel.hidesOnDeactivate = false
        newPanel.contentView = contentView
        newPanel.center()
        return newPanel
    }

    private func buildContentView() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 16
        container.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // -- Ordering mode section --
        let orderingLabel = sectionLabel("Pin Ordering")
        container.addArrangedSubview(orderingLabel)

        let recentInteractionButton = NSButton(
            radioButtonWithTitle: "Recent interaction first (default)",
            target: self,
            action: #selector(orderingModeChanged(_:))
        )
        recentInteractionButton.tag = 0
        recentInteractionButton.state = settings.orderingMode == .recentInteractionFirst ? .on : .off

        let recentPinButton = NSButton(
            radioButtonWithTitle: "Recent pin first",
            target: self,
            action: #selector(orderingModeChanged(_:))
        )
        recentPinButton.tag = 1
        recentPinButton.state = settings.orderingMode == .recentPinFirst ? .on : .off

        container.addArrangedSubview(recentInteractionButton)
        container.addArrangedSubview(recentPinButton)

        container.addArrangedSubview(separatorView())

        // -- Overlay section --
        let overlayLabel = sectionLabel("Overlay")
        container.addArrangedSubview(overlayLabel)

        let opacityRow = buildOpacityRow()
        container.addArrangedSubview(opacityRow)

        let clickThroughCheckbox = NSButton(
            checkboxWithTitle: "Click-through (pass mouse events to windows below)",
            target: self,
            action: #selector(clickThroughChanged(_:))
        )
        clickThroughCheckbox.state = settings.overlayClickThrough ? .on : .off
        container.addArrangedSubview(clickThroughCheckbox)

        return container
    }

    private func buildOpacityRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8

        let label = NSTextField(labelWithString: "Opacity:")
        label.font = .systemFont(ofSize: NSFont.systemFontSize)

        let slider = NSSlider(value: settings.overlayOpacity, minValue: 0.3, maxValue: 1.0,
                              target: self, action: #selector(opacityChanged(_:)))
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let valueLabel = NSTextField(labelWithString: opacityString(settings.overlayOpacity))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        valueLabel.identifier = NSUserInterfaceItemIdentifier("opacityValueLabel")

        row.addArrangedSubview(label)
        row.addArrangedSubview(slider)
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func separatorView() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    // MARK: - Actions

    @objc
    private func orderingModeChanged(_ sender: NSButton) {
        settings.orderingMode = sender.tag == 1 ? .recentPinFirst : .recentInteractionFirst
    }

    @objc
    private func opacityChanged(_ sender: NSSlider) {
        settings.overlayOpacity = sender.doubleValue
        // Update value label in the panel
        if let contentView = panel?.contentView,
           let label = findView(
               withIdentifier: "opacityValueLabel",
               in: contentView
           ) as? NSTextField {
            label.stringValue = opacityString(sender.doubleValue)
        }
    }

    @objc
    private func clickThroughChanged(_ sender: NSButton) {
        settings.overlayClickThrough = sender.state == .on
    }

    // MARK: - Helpers

    private func opacityString(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func findView(
        withIdentifier identifier: String,
        in view: NSView
    ) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findView(withIdentifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}
