// MARK: - SettingsView.swift
// VoiceTyper – Settings Panel
//
// A macOS-native settings sheet presented from the PopoverView.
// All toggles and controls read/write through AppState which
// persists values to UserDefaults.
//
// Created for VoiceTyper · macOS 13.0+

import SwiftUI
import ServiceManagement

// MARK: - SettingsView

/// Settings panel displayed as a sheet from the main popover.
///
/// Sections:
/// 1. General — master toggle, launch at login, sound effects
/// 2. Recognition — engine settings, language, hold threshold
/// 3. Model — download status, file size, download/delete actions
/// 4. About — version info, privacy notice
struct SettingsView: View {

    // ── State ────────────────────────────────────

    /// Shared application state (settings are read/written here).
    var appState: AppState

    /// Dismiss action for the sheet.
    @Environment(\.dismiss) private var dismiss

    /// Local error alert state for Launch-at-Login failures.
    @State private var showLoginError = false
    @State private var loginErrorMessage = ""

    // ── Body ─────────────────────────────────────

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider().opacity(0.4)
            settingsForm
        }
        .frame(width: 320, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Launch at Login", isPresented: $showLoginError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(loginErrorMessage)
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Header
    // ──────────────────────────────────────────────

    private var settingsHeader: some View {
        HStack {
            Text("Settings")
                .font(.system(.headline, design: .rounded))

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // ──────────────────────────────────────────────
    // MARK: Form
    // ──────────────────────────────────────────────

    private var settingsForm: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                generalSection
                recognitionSection
                modelSection
                aboutSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // ──────────────────────────────────────────────
    // MARK: General Section
    // ──────────────────────────────────────────────

    private var generalSection: some View {
        SettingsSectionContainer(title: "General") {
            // Enable VoiceTyper toggle
            SettingsToggleRow(
                icon: "mic.fill",
                iconColor: .green,
                title: "Enable VoiceTyper",
                subtitle: "Master on/off switch",
                isOn: Binding(
                    get: { appState.isEnabled },
                    set: { newValue in
                        appState.isEnabled = newValue
                        if !newValue { appState.currentState = .disabled }
                        else if appState.currentState == .disabled { appState.currentState = .idle }
                    }
                )
            )

            Divider().opacity(0.2)

            // Launch at Login toggle
            SettingsToggleRow(
                icon: "arrow.right.circle.fill",
                iconColor: .blue,
                title: "Launch at Login",
                subtitle: "Start when you log in",
                isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { newValue in
                        handleLaunchAtLogin(newValue)
                    }
                )
            )

            Divider().opacity(0.2)

            // Show Live Preview Overlay
            SettingsToggleRow(
                icon: "text.bubble.fill",
                iconColor: .purple,
                title: "Show Live Preview",
                subtitle: "Floating overlay while recording",
                isOn: Binding(
                    get: { appState.showLivePreview },
                    set: { appState.showLivePreview = $0 }
                )
            )

            Divider().opacity(0.2)

            // Play Sound Effects
            SettingsToggleRow(
                icon: "speaker.wave.2.fill",
                iconColor: .orange,
                title: "Play Sound Effects",
                subtitle: "Audio feedback on start/stop",
                isOn: Binding(
                    get: { appState.playSoundEffects },
                    set: { appState.playSoundEffects = $0 }
                )
            )
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Recognition Section
    // ──────────────────────────────────────────────

    private var recognitionSection: some View {
        SettingsSectionContainer(title: "Recognition") {
            // Apple Speech Fallback
            SettingsToggleRow(
                icon: "apple.logo",
                iconColor: .secondary,
                title: "Apple Speech Fallback",
                subtitle: "Use when Whisper is unavailable",
                isOn: Binding(
                    get: { appState.useAppleSpeechFallback },
                    set: { appState.useAppleSpeechFallback = $0 }
                )
            )

            Divider().opacity(0.2)

            // Language Picker
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    settingIcon("globe", color: .cyan)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Language")
                            .font(.system(.callout, weight: .medium))
                        Text("Transcription language")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("", selection: Binding(
                    get: { appState.selectedLanguage },
                    set: { appState.selectedLanguage = $0 }
                )) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.rawValue).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider().opacity(0.2)

            // Hold Threshold Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    settingIcon("timer", color: .yellow)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hold Threshold")
                            .font(.system(.callout, weight: .medium))
                        Text("Time to hold ⌥ before recording starts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(String(format: "%.1fs", appState.holdThreshold))
                        .font(.system(.caption, design: .monospaced, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }

                Stepper(
                    value: Binding(
                        get: { appState.holdThreshold },
                        set: { appState.holdThreshold = $0 }
                    ),
                    in: 0.5 ... 3.0,
                    step: 0.1
                ) {
                    EmptyView()
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Model Section
    // ──────────────────────────────────────────────

    private var modelSection: some View {
        SettingsSectionContainer(title: "Whisper Model") {
            VStack(alignment: .leading, spacing: 10) {
                // Status row
                HStack(spacing: 8) {
                    settingIcon("cpu", color: .indigo)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Whisper Base")
                            .font(.system(.callout, weight: .medium))

                        HStack(spacing: 6) {
                            modelStatusLabel
                            if appState.modelFileSize > 0 {
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(appState.modelFileSizeFormatted)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()
                }

                // Download progress or action button
                modelActionView
            }
        }
    }

    /// Displays the current download status as a coloured label.
    @ViewBuilder
    private var modelStatusLabel: some View {
        switch appState.modelDownloadStatus {
        case .downloaded:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)

        case .notDownloaded:
            Label("Not Downloaded", systemImage: "arrow.down.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)

        case .downloading:
            Label("Downloading…", systemImage: "arrow.down.circle.dotted")
                .font(.caption2)
                .foregroundStyle(.orange)

        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .help("Download failed")
        }
    }

    /// Download button or progress bar depending on state.
    @ViewBuilder
    private var modelActionView: some View {
        switch appState.modelDownloadStatus {
        case .notDownloaded, .failed:
            Button {
                appState.downloadModel()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11))
                    Text("Download Model (~150 MB)")
                        .font(.system(.caption, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                )
            }
            .buttonStyle(.plain)

        case .downloading:
            VStack(spacing: 4) {
                ProgressView(value: appState.modelDownloadProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)

                HStack {
                    Text("\(Int(appState.modelDownloadProgress * 100))%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        appState.cancelDownload()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

        case .downloaded:
            EmptyView()
        }
    }

    // ──────────────────────────────────────────────
    // MARK: About Section
    // ──────────────────────────────────────────────

    private var aboutSection: some View {
        SettingsSectionContainer(title: "About") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(appState.appVersion)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                Divider().opacity(0.2)

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)

                    Text("Fully local — no data leaves your Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // ──────────────────────────────────────────────
    // MARK: Helpers
    // ──────────────────────────────────────────────

    /// Builds a small coloured icon for a setting row.
    private func settingIcon(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.gradient)
            )
    }

    /// Registers or unregisters the app as a login item using SMAppService.
    private func handleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            appState.launchAtLogin = enabled
        } catch {
            loginErrorMessage = error.localizedDescription
            showLoginError = true
            // Revert the toggle visually.
            appState.launchAtLogin = !enabled
        }
    }
}

// MARK: - SettingsSectionContainer

/// A reusable container that groups settings rows with a section title
/// and a rounded-rectangle card background.
struct SettingsSectionContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 10) {
                content()
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
    }
}

// MARK: - SettingsToggleRow

/// A single toggle row used in settings sections.
/// Displays icon + title + subtitle on the left, toggle on the right.
struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(iconColor.gradient)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.callout, weight: .medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

// MARK: - Preview

#Preview {
    SettingsView(appState: AppState())
        .frame(width: 320, height: 520)
}
