import AppKit
import Foundation

final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isActive = false
    private var requiredModifiers: UInt
    private var requiredKeyCode: UInt16

    var isOperational: Bool { eventTap != nil }

    init(modifiers: UInt, keyCode: UInt16) {
        requiredModifiers = modifiers
        requiredKeyCode = keyCode
    }

    func updateHotkey(modifiers: UInt, keyCode: UInt16) {
        requiredModifiers = modifiers
        requiredKeyCode = keyCode
    }

    func start() -> Bool {
        if #available(macOS 10.15, *) {
            if !CGPreflightListenEventAccess() {
                CGRequestListenEventAccess()
            }
        }

        stop()

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            if manager.handleEvent(type: type, event: event) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
    }

    /// Returns `true` when the event should be consumed and not forwarded to the focused app.
    private func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        let flags = event.flags.rawValue
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            if matchesHotkey(flags: flags, keyCode: keyCode) && !isActive {
                isActive = true
                DispatchQueue.main.async { [weak self] in
                    self?.onPress?()
                }
                return true
            }
            if isActive && keyCode == requiredKeyCode {
                return true
            }
        case .keyUp:
            if isActive && keyCode == requiredKeyCode {
                isActive = false
                DispatchQueue.main.async { [weak self] in
                    self?.onRelease?()
                }
                return true
            }
            if isActive && !hasRequiredModifiers(flags) {
                isActive = false
                DispatchQueue.main.async { [weak self] in
                    self?.onRelease?()
                }
            }
        case .flagsChanged:
            if isActive && !hasRequiredModifiers(flags) {
                isActive = false
                DispatchQueue.main.async { [weak self] in
                    self?.onRelease?()
                }
            }
        default:
            break
        }

        return false
    }

    private func matchesHotkey(flags: UInt64, keyCode: UInt16) -> Bool {
        hasRequiredModifiers(flags) && keyCode == requiredKeyCode
    }

    private func hasRequiredModifiers(_ flags: UInt64) -> Bool {
        let modifierMask = UInt64(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
        let current = flags & modifierMask
        let required = UInt64(requiredModifiers) & modifierMask
        return current == required
    }
}
