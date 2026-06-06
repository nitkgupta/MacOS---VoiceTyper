// MARK: - VoiceTyperApp.swift
// VoiceTyper — macOS Menu Bar Speech-to-Text
//
// The application entry point. VoiceTyper is a menu-bar-only app with
// no dock icon (LSUIElement = true in Info.plist). The SwiftUI `App`
// body contains only a `Settings` scene — all interaction happens
// through the status bar icon and its popover.
//
// The `AppDelegate` handles:
//   • Creating the shared `AppState`
//   • Creating the `StatusBarController` (menu bar icon + popover)
//   • Creating the `VoiceTyperManager` (orchestrator)
//   • Checking required permissions on launch
//   • Starting the manager once permissions are confirmed
//   • Cleaning up on termination
//
// Copyright © 2026 VoiceTyper. All rights reserved.

import SwiftUI
import AVFoundation
import Speech

// MARK: - VoiceTyperApp

/// The main application struct. Uses `@NSApplicationDelegateAdaptor` to
/// bridge to an `AppDelegate` for lifecycle management.
///
/// The app body is an empty `Settings` scene because VoiceTyper is
/// entirely menu-bar driven. Set `LSUIElement = true` in Info.plist
/// to suppress the dock icon.
@main
struct VoiceTyperApp: App {

    /// Bridge to the AppKit lifecycle via `AppDelegate`.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible window. The entire UI lives in the status bar
        // popover and the floating HUD overlay.
        Settings {
            // Empty settings scene — settings are shown in the popover.
            EmptyView()
        }
    }
}

// MARK: - AppDelegate

/// AppKit delegate that owns the core objects and manages the app lifecycle.
///
/// Responsibilities:
/// - Creates and retains `AppState`, `StatusBarController`, and
///   `VoiceTyperManager`.
/// - Requests necessary permissions (Accessibility, Microphone, Speech).
/// - Starts the `VoiceTyperManager` once permissions are in order.
/// - Cleans up resources when the app terminates.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core Objects

    /// The shared application state, observed by the UI and manager.
    private var appState: AppState!

    /// The status bar icon and popover controller.
    private var statusBarController: StatusBarController?

    /// The main orchestrator that wires audio, transcription, and
    /// text insertion together.
    private var voiceTyperManager: VoiceTyperManager?

    // MARK: - NSApplicationDelegate

    /// Called when the application finishes launching.
    ///
    /// Sets up all core objects, checks permissions, and starts the
    /// voice-typing system.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Create the shared app state.
        let state = AppState()
        self.appState = state

        // 2. Create the status bar controller (menu bar icon + popover).
        self.statusBarController = StatusBarController(appState: state)

        // 3. Create the main orchestrator.
        let manager = VoiceTyperManager(appState: state)
        self.voiceTyperManager = manager

        // 4. Check permissions and start the system.
        Task { @MainActor in
            await self.checkPermissionsAndStart(manager: manager)
        }
    }

    /// Called when the application is about to terminate.
    ///
    /// Stops the VoiceTyperManager to release event taps, audio sessions,
    /// and other system resources cleanly.
    func applicationWillTerminate(_ notification: Notification) {
        voiceTyperManager?.stop()
        voiceTyperManager = nil
        statusBarController = nil
    }

    /// Prevents the app from terminating when the last window closes.
    /// Since VoiceTyper is a menu-bar app, there may never be a visible
    /// window, and closing the settings should not quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        return false
    }

    // MARK: - Permission Checks

    /// Checks all required permissions and starts the manager if granted.
    ///
    /// Required permissions:
    /// 1. **Accessibility** — needed for global hotkey monitoring and
    ///    AX-based text insertion.
    /// 2. **Microphone** — needed for audio capture.
    /// 3. **Speech Recognition** — needed for Apple Speech fallback.
    ///
    /// If Accessibility is not granted, an alert directs the user to
    /// System Settings. Microphone and Speech permissions are requested
    /// via their standard system dialogs.
    @MainActor
    private func checkPermissionsAndStart(manager: VoiceTyperManager) async {
        // 1. Check Accessibility permission.
        let accessibilityGranted = checkAccessibilityPermission()

        // 2. Request Microphone permission.
        let microphoneGranted = await requestMicrophonePermission()

        // 3. Request Speech Recognition permission (for Apple Speech fallback).
        await AppleSpeechEngine.requestAuthorization()

        // Always start the manager so the app is ready once permissions are granted.
        manager.start()
    }

    /// Checks whether the app has Accessibility permission.
    ///
    /// If not granted, shows an alert directing the user to System Settings
    /// and opens the Accessibility pane. Uses `AXIsProcessTrustedWithOptions`
    /// which prompts the user on first call.
    ///
    /// - Returns: `true` if Accessibility is already granted.
    private func checkAccessibilityPermission() -> Bool {
        // The options dictionary with kAXTrustedCheckOptionPrompt = true
        // causes macOS to show the system prompt if not already trusted.
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        let isTrusted = AXIsProcessTrustedWithOptions(options)

        if !isTrusted {
            // Show an informational alert.
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
                VoiceTyper needs Accessibility access to detect the \
                Option key hold gesture and insert text into other apps.

                Please grant access in System Settings → Privacy & Security \
                → Accessibility, then relaunch VoiceTyper.
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open the Accessibility pane in System Settings.
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        return isTrusted
    }

    /// Requests microphone access using the AVFoundation API.
    ///
    /// - Returns: `true` if the user grants microphone permission.
    private func requestMicrophonePermission() async -> Bool {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        switch currentStatus {
        case .authorized:
            return true

        case .notDetermined:
            // Request permission — this shows the system dialog.
            return await AVCaptureDevice.requestAccess(for: .audio)

        case .denied, .restricted:
            // Permission was previously denied. Show an alert.
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Microphone Permission Required"
                alert.informativeText = """
                    VoiceTyper needs microphone access to capture your \
                    speech for transcription.

                    Please grant access in System Settings → Privacy & \
                    Security → Microphone.
                    """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return false

        @unknown default:
            return false
        }
    }
}
