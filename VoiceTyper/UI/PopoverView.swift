// MARK: - PopoverView.swift
// VoiceTyper – Main Popover View
//
// The primary SwiftUI interface shown when the user clicks
// the menu bar icon. Displays status, controls, last
// transcription, and quick stats in a compact 300×450 pt panel.
//
// Created for VoiceTyper · macOS 13.0+

import SwiftUI

// MARK: - PopoverView

/// Main popover view anchored to the menu bar status item.
///
/// Layout (top → bottom):
/// 1. Header – app icon, title, settings gear
/// 2. Enable / Disable pill toggle
/// 3. Hold-to-speak hint
/// 4. Status indicators (state, engine, language)
/// 5. Last transcription card
/// 6. Stats row
/// 7. Quit button
struct PopoverView: View {

    // ── State ────────────────────────────────────
    /// The shared application state.
    var appState: AppState

    /// Controls navigation to the settings sheet.
    @State private var showSettings = false

    /// Drives a subtle pulsing animation on the "Hold ⌥" hint.
    @State private var hintPulse = false

    /// Tracks copy-confirmation feedback.
    @State private var didCopy = false

    // ── Constants ────────────────────────────────
    private let popoverWidth: CGFloat  = 300
    private let popoverHeight: CGFloat = 450

    // ── Body ─────────────────────────────────────
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(0.4)
            scrollableContent
        }
        .frame(width: popoverWidth, height: popoverHeight)
        .background(backgroundGradient)
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState)
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Header
    // ──────────────────────────────────────────────

    /// App icon + title + gear button.
    private var headerSection: some View {
        HStack(spacing: 10) {
            // App icon — microphone with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("VoiceTyper")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Voice to text, locally")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Settings gear button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // ──────────────────────────────────────────────
    // MARK: Scrollable Content
    // ──────────────────────────────────────────────

    private var scrollableContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                enableToggleSection
                holdToSpeakHint
                modelWarningSection
                statusSection
                lastTranscriptionCard
                statsRow
                Spacer(minLength: 8)
                quitButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Enable / Disable Toggle
    // ──────────────────────────────────────────────

    /// Big animated pill-style toggle.
    private var enableToggleSection: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                appState.isEnabled.toggle()
                if !appState.isEnabled {
                    appState.currentState = .disabled
                } else if appState.currentState == .disabled {
                    appState.currentState = .idle
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Animated pill switch
                pillSwitch(isOn: appState.isEnabled)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.isEnabled ? "Enabled" : "Disabled")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(appState.isEnabled ? .primary : .secondary)

                    Text(appState.isEnabled ? "VoiceTyper is active" : "Click to enable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                appState.isEnabled ? Color.green.opacity(0.3) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Custom pill-shaped switch indicator.
    private func pillSwitch(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.green : Color.gray.opacity(0.35))
                .frame(width: 44, height: 26)

            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .frame(width: 22, height: 22)
                .padding(.horizontal, 2)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isOn)
    }

    // ──────────────────────────────────────────────
    // MARK: Hold-to-Speak Hint
    // ──────────────────────────────────────────────

    private var holdToSpeakHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .scaleEffect(hintPulse ? 1.1 : 1.0)
                .animation(
                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: hintPulse
                )

            Text("Hold")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Keycap-style ⌥ badge
            Text("⌥")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                )

            Text("to speak")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear { hintPulse = true }
    }

    // ──────────────────────────────────────────────
    // MARK: Model Warning Section
    // ──────────────────────────────────────────────

    @ViewBuilder
    private var modelWarningSection: some View {
        if !appState.useAppleSpeechFallback && !appState.isModelDownloaded {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Model Required")
                        .font(.caption.bold())
                }
                Text("Please download the Whisper model in Settings or enable Apple Speech fallback.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.yellow.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Status Section
    // ──────────────────────────────────────────────

    private var statusSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Status")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            HStack(spacing: 12) {
                statusBadge
                engineBadge
                languageBadge
                Spacer()
            }
        }
    }

    /// Coloured pill showing the current state.
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier(shouldPulse: appState.currentState == .recording))

            Text(appState.currentState.rawValue)
                .font(.system(.caption2, design: .rounded, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(statusDotColor.opacity(0.15))
        )
    }

    /// Engine badge (Whisper / Apple Speech).
    private var engineBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: appState.engineName == "Whisper" ? "cpu" : "apple.logo")
                .font(.system(size: 9))
            Text(appState.engineName)
                .font(.system(.caption2, design: .rounded, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    /// Language badge.
    private var languageBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 9))
            Text(appState.selectedLanguage)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }

    /// Returns the colour for the status indicator dot.
    private var statusDotColor: Color {
        switch appState.currentState {
        case .idle:       return .green
        case .recording:  return .red
        case .processing, .inserting: return .orange
        case .disabled:   return .gray
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Last Transcription Card
    // ──────────────────────────────────────────────

    private var lastTranscriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last Transcription")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                // Copy button
                if !appState.lastTranscription.isEmpty {
                    Button {
                        copyToClipboard(appState.lastTranscription)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(didCopy ? "Copied" : "Copy")
                                .font(.caption2)
                        }
                        .foregroundStyle(didCopy ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Transcription text
            Text(appState.lastTranscription.isEmpty ? "No transcription yet" : appState.lastTranscription)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(appState.lastTranscription.isEmpty ? .tertiary : .primary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    // ──────────────────────────────────────────────
    // MARK: Stats Row
    // ──────────────────────────────────────────────

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(icon: "waveform.path.ecg", label: "Sessions", value: "\(appState.sessionCount)")
            Divider().frame(height: 28).opacity(0.3)
            statItem(icon: "character.cursor.ibeam", label: "Words", value: "\(appState.totalWordsTyped)")
            Divider().frame(height: 28).opacity(0.3)
            statItem(icon: "speedometer", label: "Latency", value: String(format: "%.1fs", appState.averageLatency))
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    /// Single stat column.
    private func statItem(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // ──────────────────────────────────────────────
    // MARK: Quit Button
    // ──────────────────────────────────────────────

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "power")
                    .font(.system(size: 11))
                Text("Quit VoiceTyper")
                    .font(.system(.caption, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    // ──────────────────────────────────────────────
    // MARK: Background Gradient
    // ──────────────────────────────────────────────

    /// Subtle dark gradient that gives the popover a premium feel.
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // ──────────────────────────────────────────────
    // MARK: Helpers
    // ──────────────────────────────────────────────

    /// Copies text to the system clipboard with visual feedback.
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { didCopy = false }
        }
    }
}

// MARK: - PulseModifier

/// A view modifier that adds a repeating scale pulse effect.
struct PulseModifier: ViewModifier {
    let shouldPulse: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shouldPulse && isPulsing ? 1.6 : 1.0)
            .opacity(shouldPulse && isPulsing ? 0.5 : 1.0)
            .animation(
                shouldPulse
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onChange(of: shouldPulse) { _, newValue in
                isPulsing = newValue
            }
            .onAppear {
                isPulsing = shouldPulse
            }
    }
}

// MARK: - Preview

#Preview {
    PopoverView(appState: AppState())
        .frame(width: 300, height: 450)
}
