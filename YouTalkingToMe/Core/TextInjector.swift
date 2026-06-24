import AppKit
import ApplicationServices
import Foundation

enum TextInjectionMethod: String {
    case accessibility
    case pasteboard
    case unicodeTyping
}

final class TextInjector {
    private static let clipboardRestoreDelay: TimeInterval = 0.25

    @MainActor
    func inject(_ text: String) -> (success: Bool, method: TextInjectionMethod?) {
        guard !text.isEmpty else { return (false, nil) }

        if injectViaAccessibility(text) {
            AppLogger.info("Text injected via accessibility (\(text.count) chars)")
            return (true, .accessibility)
        }

        if injectViaPasteboard(text) {
            AppLogger.info("Text injected via pasteboard (\(text.count) chars)")
            return (true, .pasteboard)
        }

        if injectViaUnicodeTyping(text) {
            AppLogger.info("Text injected via unicode typing (\(text.count) chars)")
            return (true, .unicodeTyping)
        }

        AppLogger.error("Text injection failed for \(text.count) chars")
        return (false, nil)
    }

    @MainActor
    private func injectViaAccessibility(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else {
            AppLogger.debug("Accessibility not trusted, skipping AX injection")
            return false
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusResult == .success, let focusedRef else {
            AppLogger.debug("No focused AX element (code \(focusResult.rawValue))")
            return false
        }

        let focused = focusedRef as! AXUIElement
        let setSelected = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        if setSelected == .success {
            return true
        }

        AppLogger.debug("kAXSelectedTextAttribute failed (code \(setSelected.rawValue)), trying kAXValueAttribute")

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
              let currentValue = valueRef as? String else {
            return false
        }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(focused, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            return false
        }

        let newValue = insert(text, into: currentValue, at: selectedRange(in: focused))
        let setValue = AXUIElementSetAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            newValue as CFString
        )
        return setValue == .success
    }

    @MainActor
    private func injectViaPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let savedContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard simulateCommandV() else { return false }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clipboardRestoreDelay) {
            if let savedContents {
                pasteboard.clearContents()
                pasteboard.setString(savedContents, forType: .string)
            } else {
                pasteboard.clearContents()
            }
        }

        return true
    }

    @MainActor
    private func injectViaUnicodeTyping(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        var utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return false }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return false
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyUp.keyboardSetUnicodeString(stringLength: 0, unicodeString: nil)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func selectedRange(in element: AXUIElement) -> NSRange {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let axValue = rangeRef else {
            return NSRange(location: NSNotFound, length: 0)
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
            return NSRange(location: NSNotFound, length: 0)
        }

        return NSRange(location: range.location, length: range.length)
    }

    private func insert(_ text: String, into currentValue: String, at range: NSRange) -> String {
        let nsValue = currentValue as NSString
        if range.location != NSNotFound, range.location <= nsValue.length {
            return nsValue.replacingCharacters(in: range, with: text)
        }
        return currentValue + text
    }

    private func simulateCommandV() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand

        guard let keyDown, let keyUp else { return false }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
