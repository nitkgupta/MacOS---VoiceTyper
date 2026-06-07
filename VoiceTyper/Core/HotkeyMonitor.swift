// MARK: - HotkeyMonitor.swift
// VoiceTyper — macOS Menu Bar Speech-to-Text
//
// Monitors the Option (⌥) key globally using a CGEventTap on
// `.flagsChanged` events. When the user presses and holds Option for
// a configurable duration (default 2.0 s), the `onRecordingStart`
// callback fires. When the key is subsequently released, the
// `onRecordingStop` callback fires.
//
// If Option is released before the threshold, the hold is silently
// cancelled — no callbacks fire. This prevents accidental activation
// when using normal keyboard shortcuts like ⌥Tab.
//
// Key design points:
//   • CGEventTap callback must be a C-function-compatible closure,
//     so this is a class (not an actor or struct).
//   • Events are NEVER swallowed — the callback always returns
//     `Unmanaged.passUnretained(event)` so other applications still
//     receive the key event.
//   • The CFMachPort and CFRunLoopSource are stored for proper cleanup
//     on `stop()` and `deinit`.
//   • Requires Accessibility permission (System Settings → Privacy &
//     Security → Accessibility). A convenience method opens the
//     relevant System Settings pane.
//
// Privacy:
//   No events are logged. No audio or keystrokes are recorded by this
//   class. It only observes modifier flag transitions.
//
// Copyright © 2026 VoiceTyper. All rights reserved.

import Cocoa
import ApplicationServices

// MARK: - HotkeyMonitor

/// Monitors the global Option key for press-and-hold gestures using a
/// CGEventTap. Designed to be used from the main thread.
///
/// Usage:
/// ```swift
/// let monitor = HotkeyMonitor()
/// monitor.onRecordingStart = { print("Start recording") }
/// monitor.onRecordingStop  = { print("Stop recording") }
/// monitor.start()
/// ```
final class HotkeyMonitor {

    // MARK: - Callbacks

    /// Called on the main queue when the Option key has been held for
    /// at least `holdThreshold` seconds.
    var onRecordingStart: (() -> Void)?

    /// Called on the main queue when the Option key is released after
    /// recording has started (i.e. after `onRecordingStart` fired).
    var onRecordingStop: (() -> Void)?

    // MARK: - Configuration

    /// How long (seconds) the Option key must be held before recording
    /// triggers. Clamped to [0.3, 5.0] on set.
    var holdThreshold: TimeInterval {
        didSet {
            holdThreshold = min(max(holdThreshold, 0.2), 5.0)
        }
    }

    // MARK: - State

    /// Whether the event tap is currently installed and running.
    private(set) var isRunning: Bool = false

    /// Whether recording is currently active (threshold was reached and
    /// Option is still held).
    private(set) var isRecordingActive: Bool = false

    // MARK: - Private Properties

    /// The CFMachPort backing the CGEventTap.
    fileprivate var eventTapPort: CFMachPort?

    /// The run loop source that feeds events from the mach port.
    private var runLoopSource: CFRunLoopSource?

    /// Timestamp of the most recent Option key-down event.
    private var optionDownTimestamp: Date?

    /// Delayed work item that fires after `holdThreshold` seconds.
    /// Cancelled if Option is released early.
    private var thresholdTimer: DispatchWorkItem?

    // MARK: - Initialisation

    /// Creates a new HotkeyMonitor.
    ///
    /// - Parameter holdThreshold: Seconds the Option key must be held
    ///   before activation. Default is 2.0. Clamped to [0.3, 5.0].
    init(holdThreshold: TimeInterval = 0.3) {
        self.holdThreshold = min(max(holdThreshold, 0.2), 5.0)
    }

    deinit {
        stop()
    }

    // MARK: - Accessibility

    /// Returns `true` if this process is trusted for Accessibility access.
    ///
    /// CGEventTap requires Accessibility permission. If this returns
    /// `false`, call `requestAccessibilityPermission()` to prompt the
    /// user.
    static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Opens the Accessibility pane in System Settings so the user can
    /// grant permission to VoiceTyper.
    ///
    /// On macOS 13+ this opens the Privacy & Security → Accessibility
    /// pane directly. The `kAXTrustedCheckOptionPrompt` key also
    /// triggers the native system prompt.
    static func requestAccessibilityPermission() {
        // Trigger the native system prompt dialog.
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Also open System Settings directly for better discoverability.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Start / Stop

    /// Whether `start()` was called but the event tap failed to install
    /// (typically because Accessibility permission was not yet granted).
    /// When `true`, `restartIfNeeded()` will retry installation.
    private(set) var needsRestart: Bool = false

    /// Installs the CGEventTap and begins monitoring Option key events.
    ///
    /// If Accessibility access has not been granted, this method prints
    /// a warning but still attempts installation — macOS will silently
    /// disable the tap until permission is granted.
    ///
    /// Does nothing if already running.
    func start() {
        guard !isRunning else { return }

        if !Self.isAccessibilityTrusted() {
            print("[HotkeyMonitor] ⚠️ Accessibility access not granted. Event tap may not work.")
        }

        // Create a mutable pointer to self that we pass as `userInfo`
        // into the C callback. The callback casts it back to recover
        // the HotkeyMonitor instance.
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        // We only need `.flagsChanged` events — these fire whenever a
        // modifier key (Shift, Control, Option, Command) transitions.
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        // Create the event tap. `.cghidEventTap` is the earliest point
        // in the event pipeline, giving us first look at the event.
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventCallback,
            userInfo: selfPointer
        ) else {
            print("[HotkeyMonitor] ❌ Failed to create CGEventTap. Check Accessibility permissions.")
            // Mark that we need to retry once permission is granted.
            needsRestart = true
            return
        }

        needsRestart = false
        eventTapPort = port

        // Wrap the mach port in a run loop source and add it to the
        // current run loop (main run loop).
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

        // Enable the tap (it starts enabled, but be explicit).
        CGEvent.tapEnable(tap: port, enable: true)

        isRunning = true
    }

    /// Retries event tap installation if the initial `start()` failed
    /// due to missing Accessibility permission.
    ///
    /// Call this periodically (e.g. from a timer) after the user has
    /// been prompted for Accessibility access. Once the tap installs
    /// successfully, `needsRestart` becomes `false` and further calls
    /// are no-ops.
    func restartIfNeeded() {
        guard needsRestart, !isRunning else { return }

        // Only retry if permission has actually been granted now.
        guard Self.isAccessibilityTrusted() else { return }

        print("[HotkeyMonitor] ✅ Accessibility permission granted. Retrying event tap installation.")
        start()
    }

    /// Removes the CGEventTap and stops monitoring.
    ///
    /// Any pending threshold timer is cancelled. Does nothing if not
    /// running.
    func stop() {
        guard isRunning else { return }

        // Cancel any in-flight threshold timer.
        cancelThresholdTimer()

        // Remove the run loop source.
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        // Disable and release the mach port.
        if let port = eventTapPort {
            CGEvent.tapEnable(tap: port, enable: false)
            // CFMachPort is automatically invalidated when all references
            // are released. Setting to nil drops our reference.
            eventTapPort = nil
        }

        // Reset transient state.
        isRecordingActive = false
        optionDownTimestamp = nil
        needsRestart = false
        isRunning = false
    }

    // MARK: - Event Handling (called from the C callback)

    /// Processes a `.flagsChanged` event to detect Option key transitions.
    ///
    /// - Parameter event: The CGEvent representing a modifier key change.
    fileprivate func handleFlagsChanged(_ event: CGEvent) {
        let flags = event.flags

        // Check if the Option (Alternate) modifier is currently pressed.
        let optionIsDown = flags.contains(.maskAlternate)

        // Also check that NO other modifiers are simultaneously held.
        // This prevents triggering on combos like ⌘⌥ or ⌃⌥.
        let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
        let hasOtherModifiers = !flags.intersection(otherModifiers).isEmpty

        if optionIsDown && !hasOtherModifiers {
            handleOptionDown()
        } else {
            handleOptionUp()
        }
    }

    // MARK: - Option Key Down

    /// Called when the Option key transitions to the down state (with
    /// no other modifiers held).
    private func handleOptionDown() {
        // Ignore if we already have an active press tracked.
        guard optionDownTimestamp == nil else { return }

        // Record the press timestamp.
        optionDownTimestamp = Date()

        // Schedule a delayed work item that will fire after the
        // threshold duration. If Option is released early, we cancel it.
        let timer = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Double-check that Option is still logically held.
            // (The timer might fire just as the key is released.)
            guard self.optionDownTimestamp != nil else { return }

            self.isRecordingActive = true
            self.onRecordingStart?()
        }

        thresholdTimer = timer
        DispatchQueue.main.asyncAfter(
            deadline: .now() + holdThreshold,
            execute: timer
        )
    }

    // MARK: - Option Key Up

    /// Called when the Option key transitions to the up state, or when
    /// another modifier is pressed alongside Option.
    private func handleOptionUp() {
        // Clear the press timestamp regardless.
        optionDownTimestamp = nil

        if isRecordingActive {
            // Option was held past the threshold and recording is
            // active — signal stop.
            isRecordingActive = false
            onRecordingStop?()
        }

        // Cancel the threshold timer if it hasn't fired yet
        // (i.e. Option was released before the threshold).
        cancelThresholdTimer()
    }

    // MARK: - Timer Management

    /// Cancels the pending threshold timer, if any.
    private func cancelThresholdTimer() {
        thresholdTimer?.cancel()
        thresholdTimer = nil
    }
}

// MARK: - CGEventTap C Callback

/// The C-compatible callback function for the CGEventTap.
///
/// CGEvent tap callbacks must be plain C functions (or static/global
/// closures with no captures). We pass the `HotkeyMonitor` instance
/// as `userInfo` and cast it back here.
///
/// **Important:** This callback NEVER swallows events. It always
/// returns `Unmanaged.passUnretained(event)` so that the event
/// continues down the event pipeline to other applications.
///
/// - Parameters:
///   - proxy: The event tap proxy (unused).
///   - type: The event type. We check for `.tapDisabledByTimeout`
///     to re-enable the tap if macOS disables it.
///   - event: The CGEvent to inspect.
///   - userInfo: An opaque pointer to the `HotkeyMonitor` instance.
/// - Returns: The unmodified event.
private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // If macOS disables the tap due to timeout (the callback took too
    // long), re-enable it immediately.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if let port = monitor.eventTapPort {
                CGEvent.tapEnable(tap: port, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // Only process flagsChanged events.
    guard type == .flagsChanged else {
        return Unmanaged.passUnretained(event)
    }

    // Recover the HotkeyMonitor instance from the opaque pointer.
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    // Dispatch to the monitor's handler.
    monitor.handleFlagsChanged(event)

    // NEVER swallow the event — pass it through unmodified.
    return Unmanaged.passUnretained(event)
}
