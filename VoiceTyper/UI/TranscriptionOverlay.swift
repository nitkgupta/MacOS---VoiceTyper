// MARK: - TranscriptionOverlay.swift
// VoiceTyper – Floating HUD Overlay
//
// A non-activating floating panel that appears during recording.
// Shows an animated waveform driven by microphone amplitude and
// live partial transcription text. Fades out 1.5 s after
// transcription completes.
//
// Created for VoiceTyper · macOS 13.0+

import AppKit
import SwiftUI

// ═══════════════════════════════════════════════════
// MARK: - OverlayWindowController
// ═══════════════════════════════════════════════════

/// Manages the lifecycle of the floating transcription HUD panel.
///
/// Usage:
/// ```swift
/// let overlay = OverlayWindowController(appState: appState)
/// overlay.showOverlay()   // fade in
/// overlay.hideOverlay()   // fade out after 1.5 s delay
/// ```
final class OverlayWindowController {

    // ── Properties ───────────────────────────────

    /// The floating NSPanel that hosts the overlay content.
    private var panel: NSPanel?

    /// Shared app state for amplitude and transcription text.
    private let appState: AppState

    /// Timer used for the 1.5 s auto-dismiss delay.
    private var dismissTimer: Timer?

    /// Whether the overlay is currently visible.
    private(set) var isVisible = false

    // ── Panel geometry ───────────────────────────

    /// Width of the overlay HUD.
    private let panelWidth: CGFloat = 400

    /// Height of the overlay HUD.
    private let panelHeight: CGFloat = 80

    /// Distance from the bottom of the screen.
    private let bottomOffset: CGFloat = 100

    /// Corner radius of the panel.
    private let cornerRadius: CGFloat = 16

    // ── Initialisation ───────────────────────────

    /// Creates the overlay controller.
    ///
    /// - Parameter appState: The shared `AppState` observable.
    init(appState: AppState) {
        self.appState = appState
    }

    // ──────────────────────────────────────────────
    // MARK: Show / Hide
    // ──────────────────────────────────────────────

    /// Presents the overlay with a smooth fade-in animation.
    func showOverlay() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        // Position at bottom-center of the main screen.
        positionPanel(panel)

        // Fade in.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isVisible = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }
    }

    /// Hides the overlay with a fade-out animation.
    ///
    /// - Parameter delay: Seconds to wait before fading out (default 0).
    func hideOverlay(delay: TimeInterval = 0) {
        guard isVisible, let panel else { return }

        dismissTimer?.invalidate()

        if delay > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.performHide(panel)
            }
        } else {
            performHide(panel)
        }
    }

    /// Hides with the standard 1.5 s post-transcription delay.
    func hideAfterTranscription() {
        hideOverlay(delay: 1.5)
    }

    // ──────────────────────────────────────────────
    // MARK: Panel Creation
    // ──────────────────────────────────────────────

    /// Creates and configures the floating NSPanel.
    private func createPanel() {
        // Content rect — will be repositioned later.
        let contentRect = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)

        // Create the panel with HUD and non-activating styles.
        let overlayPanel = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: true
        )

        // Panel configuration.
        overlayPanel.level = .floating
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = true
        overlayPanel.hidesOnDeactivate = false
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlayPanel.isMovableByWindowBackground = false
        overlayPanel.titleVisibility = .hidden
        overlayPanel.titlebarAppearsTransparent = true

        // Embed the SwiftUI content.
        let overlayContent = OverlayContentView(appState: appState)
        let hostingView = NSHostingView(rootView: overlayContent)
        hostingView.frame = contentRect

        // Apply rounded corners via a mask layer.
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = cornerRadius
        hostingView.layer?.masksToBounds = true

        overlayPanel.contentView = hostingView

        self.panel = overlayPanel
    }

    // ──────────────────────────────────────────────
    // MARK: Positioning
    // ──────────────────────────────────────────────

    /// Centers the panel horizontally at the bottom of the main screen.
    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - (panelWidth / 2)
        let y = screenFrame.minY + bottomOffset

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // ──────────────────────────────────────────────
    // MARK: Private
    // ──────────────────────────────────────────────

    /// Performs the actual fade-out and hides the panel.
    private func performHide(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.isVisible = false
        })
    }
}

// ═══════════════════════════════════════════════════
// MARK: - OverlayContentView
// ═══════════════════════════════════════════════════

/// The SwiftUI content inside the floating overlay panel.
///
/// Shows an animated waveform on the left and the partial
/// transcription text on the right, over a dark translucent
/// background with rounded corners.
struct OverlayContentView: View {

    /// Shared app state for amplitude and partial text.
    var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            // Waveform visualisation
            WaveformView(amplitude: appState.currentAmplitude)
                .frame(width: 80, height: 50)

            // Partial transcription text
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Recording indicator dot
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                        .modifier(OverlayPulse())

                    Text("Recording…")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(appState.partialTranscription.isEmpty
                     ? "Listening…"
                     : appState.partialTranscription)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.15), value: appState.partialTranscription)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: 400, height: 80)
        .background(overlayBackground)
    }

    /// Dark translucent background with border.
    private var overlayBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}

// ═══════════════════════════════════════════════════
// MARK: - WaveformView
// ═══════════════════════════════════════════════════

/// An animated waveform visualiser made of vertical bars.
///
/// Each bar's height is derived from the input `amplitude`
/// plus a per-bar random offset, creating an organic,
/// audio-reactive wave pattern.
struct WaveformView: View {

    /// Current microphone amplitude (0…1).
    let amplitude: Float

    /// Number of vertical bars in the waveform.
    private let barCount = 24

    /// Timer-driven phase offset that keeps bars animating
    /// even when the amplitude is constant.
    @State private var phase: Double = 0

    /// Timer that advances the phase.
    private let animationTimer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0 ..< barCount, id: \.self) { index in
                WaveformBar(
                    height: barHeight(for: index),
                    color: barColor(for: index)
                )
            }
        }
        .onReceive(animationTimer) { _ in
            withAnimation(.easeInOut(duration: 0.08)) {
                phase += 0.3
            }
        }
    }

    // ── Height Calculation ───────────────────────

    /// Computes the height fraction (0…1) for a bar at the given index.
    ///
    /// Uses a sine wave modulated by the microphone amplitude to create
    /// a natural, audio-reactive pattern.
    private func barHeight(for index: Int) -> CGFloat {
        let normalised  = CGFloat(index) / CGFloat(barCount)
        let sine        = sin(normalised * .pi * 2 + phase)
        let base        = 0.15                                      // minimum height
        let ampFactor   = CGFloat(amplitude) * 0.8                  // amplitude contribution
        let waveContrib = (sine + 1) / 2 * 0.3                     // wave shape contribution
        return min(1.0, base + ampFactor * (0.5 + waveContrib))
    }

    /// Gradient colour for each bar — centre bars are brighter.
    private func barColor(for index: Int) -> Color {
        let centre   = CGFloat(barCount) / 2.0
        let distance = abs(CGFloat(index) - centre) / centre       // 0 at centre, 1 at edges
        let hue      = 0.0 + distance * 0.05                       // subtle hue shift
        let brightness = 1.0 - distance * 0.3
        return Color(hue: hue, saturation: 0.8, brightness: brightness)
    }
}

// MARK: - WaveformBar

/// A single animated vertical bar in the waveform.
struct WaveformBar: View {
    /// Normalised height (0…1).
    let height: CGFloat
    /// Bar fill colour.
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(maxHeight: .infinity, alignment: .center)
            .scaleEffect(y: height, anchor: .center)
            .animation(.easeInOut(duration: 0.12), value: height)
    }
}

// MARK: - OverlayPulse

/// A modifier that adds a pulsing opacity effect to the recording dot.
struct OverlayPulse: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Preview

#Preview("Overlay Content") {
    let state = AppState()
    // Simulate active recording.
    let _ = {
        state.currentAmplitude = 0.6
        state.partialTranscription = "Hello, this is a test transcription coming through…"
    }()

    OverlayContentView(appState: state)
        .frame(width: 400, height: 80)
        .padding(40)
        .background(Color.black)
}
