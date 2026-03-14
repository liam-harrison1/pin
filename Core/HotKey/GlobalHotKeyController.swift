@preconcurrency import Carbon
import Foundation

public enum DeskPinsHotKeyAction: UInt32, Sendable {
    case toggleCurrentWindowPin = 1
}

public struct DeskPinsHotKeyDescriptor: Sendable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var displayString: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, displayString: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.displayString = displayString
    }

    public static let defaultToggleCurrentWindowPin = DeskPinsHotKeyDescriptor(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
        displayString: "Control-Option-Command-P"
    )
}

public enum DeskPinsHotKeyRegistrationError: Error, Sendable, Equatable, CustomStringConvertible {
    case installHandler(OSStatus)
    case registerHotKey(OSStatus)

    public var description: String {
        switch self {
        case .installHandler(let status):
            return "DeskPins could not install the global hot key handler (\(status))."
        case .registerHotKey(let status):
            return "DeskPins could not register the global hot key (\(status))."
        }
    }
}

public final class DeskPinsGlobalHotKeyController {
    private let actionHandler: @Sendable (DeskPinsHotKeyAction) -> Void
    private var registeredHotKeys: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private var actionByID: [UInt32: DeskPinsHotKeyAction] = [:]

    public init(actionHandler: @escaping @Sendable (DeskPinsHotKeyAction) -> Void) {
        self.actionHandler = actionHandler
    }

    public func registerDefaultHotKeys() throws {
        try register(
            descriptor: .defaultToggleCurrentWindowPin,
            action: .toggleCurrentWindowPin
        )
    }

    public func unregisterAll() {
        registeredHotKeys.forEach { hotKeyRef in
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }
        registeredHotKeys.removeAll()
        actionByID.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              let action = actionByID[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        actionHandler(action)
        return noErr
    }

    private func register(
        descriptor: DeskPinsHotKeyDescriptor,
        action: DeskPinsHotKeyAction
    ) throws {
        try ensureEventHandlerInstalled()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: 0x4453504E,
            id: action.rawValue
        )
        let status = RegisterEventHotKey(
            descriptor.keyCode,
            descriptor.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            throw DeskPinsHotKeyRegistrationError.registerHotKey(status)
        }

        actionByID[action.rawValue] = action
        registeredHotKeys.append(hotKeyRef)
    }

    private func ensureEventHandlerInstalled() throws {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            deskPinsHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            throw DeskPinsHotKeyRegistrationError.installHandler(status)
        }
    }
}

private func deskPinsHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let controller = Unmanaged<DeskPinsGlobalHotKeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return controller.handleHotKeyEvent(event)
}
