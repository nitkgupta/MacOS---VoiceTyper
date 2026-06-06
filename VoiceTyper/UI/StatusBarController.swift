// MARK: - StatusBarController.swift
// VoiceTyper – Menu Bar Status Item Controller
//
// Owns the NSStatusItem that lives in the macOS menu bar.
// Manages icon animations (idle / recording / processing / disabled)
// and toggles an NSPopover containing the main PopoverView.
//
// Created for VoiceTyper · macOS 13.0+

import AppKit
import Combine
import SwiftUI

// MARK: - StatusBarController

/// Manages the persistent `NSStatusItem` in the macOS menu bar.
///
/// Responsibilities:
/// - Display the microphone icon with state-appropriate appearance
/// - Animate the icon (pulse red during recording, spinner while processing)
/// - Toggle an `NSPopover` that embeds `PopoverView` via `NSHostingView`
/// - Close the popover when the user clicks outside of it
///
/// Usage:
/// ```swift
/// let appState = AppState()
/// let controller = StatusBarController(appState: appState)
/// ```
@MainActor
final class StatusBarController: NSObject, ObservableObject {

    // ──────────────────────────────────────────────
    // MARK: Properties
    // ──────────────────────────────────────────────

    /// The system status bar item. Retained for the lifetime of the app.
    private var statusItem: NSStatusItem

    /// Popover shown when the user clicks the menu bar icon.
    private let popover: NSPopover

    /// Shared application state observed to drive icon changes.
    private let appState: AppState

    /// Observation token for AppState status changes.
    private var statusObservation: AnyCancellable?

    /// Timer used for icon pulse / spin animations.
    private var animationTimer: Timer?

    /// Tracks the current phase of a pulse or spin animation.
    private var animationPhase: CGFloat = 0

    /// Event monitor that closes the popover when clicking outside.
    private var eventMonitor: Any?

    // ──────────────────────────────────────────────
    // MARK: Initialisation
    // ──────────────────────────────────────────────

    /// Creates the status bar controller and installs the menu bar item.
    ///
    /// - Parameter appState: The shared `AppState` observable to observe.
    init(appState: AppState) {
        self.appState = appState

        // Create the status item with a variable-width button.
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Configure the popover.
        self.popover = NSPopover()
        self.popover.contentSize = NSSize(width: 300, height: 450)
        self.popover.behavior = .transient   // auto-close on focus loss
        self.popover.animates = true

        super.init()

        // Embed the SwiftUI PopoverView inside the popover.
        let contentView = PopoverView(appState: appState)
        self.popover.contentViewController = NSHostingController(rootView: contentView)

        // Configure the status bar button appearance.
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "mic.fill",
                accessibilityDescription: "VoiceTyper"
            )
            button.image?.isTemplate = true   // respects menu bar dark/light
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Set the initial icon state.
        showIdle()

        // Observe status changes on AppState to update the icon.
        startObservingState()
    }


    // ──────────────────────────────────────────────
    // MARK: State Observation
    // ──────────────────────────────────────────────

    /// Starts a polling timer that watches `appState.currentState` for changes.
    ///
    /// Because `@Observable` doesn't natively produce Combine publishers,
    /// we use a lightweight display-link-style timer to poll the status.
    private func startObservingState() {
        // Use a 0.1s repeating timer to check for state transitions.
        var lastStatus: VoiceTyperState = appState.currentState
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = self.appState.currentState
            guard current != lastStatus else { return }
            lastStatus = current
            DispatchQueue.main.async {
                switch current {
                case .idle:       self.showIdle()
                case .recording:  self.showRecording()
                case .processing: self.showProcessing()
                case .inserting: self.showProcessing()
                case .disabled:   self.showDisabled()
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Public Icon Methods
    // ──────────────────────────────────────────────

    /// Sets the icon to the default idle state (white template mic).
    func showIdle() {
        stopAnimationTimer()
        updateIcon(symbolName: "mic.fill", tintColor: nil, isTemplate: true)
    }

    /// Animates a pulsing red microphone to indicate active recording.
    func showRecording() {
        stopAnimationTimer()
        animationPhase = 0

        // Pulse between full red and dimmed red every 0.5 s.
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.animationPhase += 1
            let alpha: CGFloat = self.animationPhase.truncatingRemainder(dividingBy: 2) == 0 ? 1.0 : 0.45
            let tint = NSColor.systemRed.withAlphaComponent(alpha)
            self.updateIcon(symbolName: "mic.fill", tintColor: tint, isTemplate: false)

            // Also add a subtle scale effect on the button layer.
            let scale: CGFloat = alpha == 1.0 ? 1.0 : 0.9
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.allowsImplicitAnimation = true
                button.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            }
        }
        // Fire immediately for the first frame.
        updateIcon(symbolName: "mic.fill", tintColor: .systemRed, isTemplate: false)
    }

    /// Shows a spinning progress indicator to signal transcription processing.
    func showProcessing() {
        stopAnimationTimer()
        animationPhase = 0

        // Cycle through three SF Symbol variants to simulate a spinner.
        let spinnerFrames = [
            "arrow.trianglehead.2.clockwise",
            "arrow.trianglehead.2.clockwise",
            "arrow.trianglehead.2.clockwise"
        ]

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.animationPhase += 1

            // Rotate the icon by adjusting the button's layer transform.
            let angle = self.animationPhase * 45.0 * (.pi / 180.0)
            let frameIndex = Int(self.animationPhase) % spinnerFrames.count
            self.updateIcon(
                symbolName: spinnerFrames[frameIndex],
                tintColor: .systemOrange,
                isTemplate: false
            )

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.allowsImplicitAnimation = true
                button.layer?.setAffineTransform(CGAffineTransform(rotationAngle: angle))
            }
        }
        updateIcon(symbolName: "arrow.trianglehead.2.clockwise", tintColor: .systemOrange, isTemplate: false)
    }

    /// Dims the icon to indicate VoiceTyper is disabled.
    func showDisabled() {
        stopAnimationTimer()
        updateIcon(symbolName: "mic.slash.fill", tintColor: .tertiaryLabelColor, isTemplate: false)
    }

    // ──────────────────────────────────────────────
    // MARK: Popover Toggle
    // ──────────────────────────────────────────────

    /// Toggles the popover on or off relative to the status bar button.
    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    /// Opens the popover anchored to the status bar button.
    private func openPopover() {
        guard let button = statusItem.button else { return }

        // Refresh the SwiftUI view's content before showing.
        let contentView = PopoverView(appState: appState)
        popover.contentViewController = NSHostingController(rootView: contentView)

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Install a global event monitor to close on outside clicks.
        installEventMonitor()
    }

    /// Closes the popover and removes the event monitor.
    private func closePopover() {
        popover.performClose(nil)
        removeEventMonitor()
    }

    // ──────────────────────────────────────────────
    // MARK: Event Monitor (close-on-click-outside)
    // ──────────────────────────────────────────────

    /// Installs a global event monitor for left / right mouse clicks
    /// that fall outside the popover, causing it to dismiss.
    private func installEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    /// Removes the global event monitor.
    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Private Helpers
    // ──────────────────────────────────────────────

    /// Updates the status bar button's icon with optional tint color.
    ///
    /// - Parameters:
    ///   - symbolName: The SF Symbol name.
    ///   - tintColor: An optional tint; pass `nil` for template mode.
    ///   - isTemplate: Whether the image should be a template image.
    private func updateIcon(symbolName: String, tintColor: NSColor?, isTemplate: Bool) {
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        var image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "VoiceTyper")
        image = image?.withSymbolConfiguration(config)

        if let tint = tintColor, !isTemplate {
            // Create a tinted copy of the image.
            let tinted = image?.copy() as? NSImage ?? NSImage()
            tinted.lockFocus()
            tint.set()
            let rect = NSRect(origin: .zero, size: tinted.size)
            rect.fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.isTemplate = false
            button.image = tinted
        } else {
            image?.isTemplate = isTemplate
            button.image = image
        }
    }

    /// Stops and releases the animation timer.
    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationPhase = 0

        // Reset any transform applied during animation.
        if let button = statusItem.button {
            button.layer?.setAffineTransform(.identity)
        }
    }
}
