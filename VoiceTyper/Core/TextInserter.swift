// MARK: - TextInserter.swift
// VoiceTyper — macOS Menu Bar Speech-to-Text
//
// Inserts transcribed text into the currently focused text field in any
// application. Two strategies are tried in order:
//
//   Strategy A (Accessibility API):
//     Reads the focused UI element via AXUIElement, determines the cursor
//     position from the selected text range, and writes the transcribed
//     text at that position by updating kAXValueAttribute.
//
//   Strategy B (Clipboard + Cmd+V):
//     Saves the current pasteboard, sets the transcribed text, simulates
//     Cmd+V via CGEvent, then restores the original clipboard after a
//     short delay.
//
// Thread Safety:
//   All Accessibility calls execute on the main queue.
//   The clipboard fallback also dispatches to main for CGEvent posting.
//
// Privacy:
//   Nothing is logged to disk. All operations are in-memory only.
//
// Copyright © 2026 VoiceTyper. All rights reserved.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

// MARK: - TextInserter

/// Provides a single `insertText(_:)` entry point that places transcribed
/// text into whatever text field currently has keyboard focus, across any
/// application on the system.
final class TextInserter: @unchecked Sendable {

    // MARK: - Singleton (optional convenience — callers may also create instances)

    /// Shared instance for convenience. The class is stateless, so a
    /// singleton is safe.
    static let shared = TextInserter()

    // MARK: - Initialisation

    init() {}

    // MARK: - Public API

    /// Insert `text` into the currently focused text field.
    ///
    /// Tries the Accessibility API first (Strategy A). If that fails for
    /// any reason — no focused element, read-only field, non-native control
    /// — falls through to clipboard simulation (Strategy B).
    ///
    /// - Parameter text: The transcribed text to insert.
    func insertText(_ text: String) {
        // All AX calls and CGEvent posting must happen on the main thread.
        if Thread.isMainThread {
            performInsertion(text)
        } else {
            DispatchQueue.main.sync {
                self.performInsertion(text)
            }
        }
    }

    // MARK: - Private Orchestration

    /// Attempts Strategy A, then falls through to Strategy B on failure.
    private func performInsertion(_ text: String) {
        let didInsertViaAX = insertViaAccessibility(text)
        if !didInsertViaAX {
            insertViaClipboard(text)
        }
    }

    // MARK: - Strategy A: Accessibility API

    /// Attempts to insert `text` at the current cursor position using
    /// the macOS Accessibility API.
    ///
    /// Steps:
    /// 1. Get the system-wide AXUIElement.
    /// 2. Copy `kAXFocusedUIElementAttribute` to find the focused control.
    /// 3. Read the current `kAXValueAttribute` (the field's full text).
    /// 4. Read `kAXSelectedTextRangeAttribute` to find cursor position.
    /// 5. Splice the new text in at the cursor.
    /// 6. Write the updated value back via `AXUIElementSetAttributeValue`.
    /// 7. Move the cursor to the end of the inserted text.
    ///
    /// - Returns: `true` if insertion succeeded, `false` otherwise.
    private func insertViaAccessibility(_ text: String) -> Bool {
        // 1. System-wide accessibility element.
        let systemWide = AXUIElementCreateSystemWide()

        // 2. Get the currently focused UI element.
        var focusedElementRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusResult == .success,
              let focusedElement = focusedElementRef else {
            return false
        }
        // swiftlint:disable:next force_cast
        let element = focusedElement as! AXUIElement

        // 3. Read the current text value.
        var currentValueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &currentValueRef
        )

        // If we can read the value, we splice; otherwise try setting
        // selected text as an alternative.
        if valueResult == .success,
           let currentValue = currentValueRef as? String {
            return insertBySplicingValue(
                element: element,
                currentValue: currentValue,
                newText: text
            )
        }

        // Alternative: try setting kAXSelectedTextAttribute directly.
        // Some controls (e.g. NSTextView) support writing selected text.
        return insertViaSelectedText(element: element, text: text)
    }

    /// Splices `newText` into `currentValue` at the cursor position, then
    /// writes the full string back to the element.
    private func insertBySplicingValue(
        element: AXUIElement,
        currentValue: String,
        newText: String
    ) -> Bool {
        // 4. Get the selected text range (cursor position).
        var rangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )

        var insertionIndex = currentValue.count // Default: end of text.
        var selectionLength = 0

        if rangeResult == .success, let rangeValue = rangeRef {
            var cfRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange) {
                insertionIndex = cfRange.location
                selectionLength = cfRange.length
            }
        }

        // 5. Splice the new text into the existing value.
        //    If there is a selection, the new text replaces it.
        let nsString = currentValue as NSString
        let safeLocation = min(insertionIndex, nsString.length)
        let safeLength = min(selectionLength, nsString.length - safeLocation)
        let replacementRange = NSRange(location: safeLocation, length: safeLength)
        let updatedValue = nsString.replacingCharacters(in: replacementRange, with: newText)

        // 6. Write the updated value back.
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            updatedValue as CFTypeRef
        )
        guard setResult == .success else {
            return false
        }

        // 7. Move cursor to end of inserted text.
        let newCursorPosition = safeLocation + newText.count
        moveCursor(in: element, to: newCursorPosition)

        return true
    }

    /// Inserts text by setting `kAXSelectedTextAttribute`.
    /// This replaces whatever is currently selected (or inserts at cursor
    /// if the selection is empty).
    private func insertViaSelectedText(element: AXUIElement, text: String) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    /// Moves the cursor (insertion point) in `element` to `position`.
    private func moveCursor(in element: AXUIElement, to position: Int) {
        var range = CFRange(location: position, length: 0)
        guard let axRange = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            axRange
        )
    }

    // MARK: - Strategy B: Clipboard + Cmd+V

    /// Inserts `text` by temporarily placing it on the pasteboard and
    /// simulating a Cmd+V keystroke. The original pasteboard contents are
    /// restored after a delay.
    ///
    /// Uses `.cghidEventTap` for event posting, which works reliably
    /// across all applications including Terminal.app.
    private func insertViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // 1. Save current clipboard contents.
        let savedItems = savePasteboardContents(pasteboard)

        // 2. Set new text on the pasteboard.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Simulate Cmd+V with a delay to allow the pasteboard server
        //    to sync. Terminal and some other apps need extra time to
        //    pick up pasteboard changes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulatePaste()

            // 4. Restore original clipboard after the paste has had
            //    time to process. Use a longer delay to be safe across
            //    all apps (Terminal can be slow).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.restorePasteboardContents(pasteboard, items: savedItems)
            }
        }
    }

    // MARK: - Clipboard Helpers

    /// A lightweight representation of a single pasteboard item.
    private struct PasteboardItem {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    /// Reads all current items from the pasteboard and returns them
    /// as an array of `PasteboardItem` for later restoration.
    private func savePasteboardContents(
        _ pasteboard: NSPasteboard
    ) -> [PasteboardItem] {
        var saved: [PasteboardItem] = []
        guard let types = pasteboard.types else { return saved }
        for type in types {
            if let data = pasteboard.data(forType: type) {
                saved.append(PasteboardItem(type: type, data: data))
            }
        }
        return saved
    }

    /// Writes previously saved items back to the pasteboard.
    private func restorePasteboardContents(
        _ pasteboard: NSPasteboard,
        items: [PasteboardItem]
    ) {
        pasteboard.clearContents()
        if items.isEmpty { return }

        // Declare all types first, then write data for each.
        let types = items.map(\.type)
        pasteboard.declareTypes(types, owner: nil)
        for item in items {
            pasteboard.setData(item.data, forType: item.type)
        }
    }

    // MARK: - CGEvent Helpers

    /// Simulates a Cmd+V paste keystroke using the Core Graphics event API.
    ///
    /// Creates a key-down and key-up pair for the 'V' key with the
    /// `.maskCommand` flag set, then posts them to the HID event tap.
    /// Using `.cghidEventTap` ensures the event reaches all apps
    /// including Terminal.app.
    private func simulatePaste() {
        // Virtual key code for 'v' is 9 (from Carbon HIToolbox).
        let vKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_V)
        
        // Use hidSystemState to ensure the system processes the event correctly.
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // Key down with Command modifier.
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: vKeyCode,
            keyDown: true
        ) else { return }
        keyDown.flags = .maskCommand

        // Key up with Command modifier.
        guard let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: vKeyCode,
            keyDown: false
        ) else { return }
        keyUp.flags = .maskCommand

        // Post events to the HID event tap — this is the most reliable
        // tap point and works with Terminal.app and other apps that
        // ignore session-level event taps.
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
