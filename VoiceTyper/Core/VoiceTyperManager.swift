// MARK: - VoiceTyperManager.swift
// VoiceTyper — macOS Menu Bar Speech-to-Text
//
// Main orchestrator that wires every subsystem together and drives the
// state machine:
//
//   IDLE → RECORDING → PROCESSING → INSERTING → IDLE
//
// Responsibilities:
//   • Owns HotkeyMonitor, AudioEngine, transcription engine, TextInserter,
//     and OverlayWindowController instances.
//   • Reacts to hotkey events to start/stop recording.
//   • Feeds captured audio samples to the selected transcription engine.
//   • Applies smart punctuation post-processing.
//   • Detects prolonged silence and auto-stops recording.
//   • Plays sound effects for session start/stop.
//   • Inserts transcribed text and updates session statistics.
//
// Privacy:
//   No audio is written to disk. No network calls.
//   Nothing is logged to disk.
//
// Copyright © 2026 VoiceTyper. All rights reserved.

import AppKit
import AVFoundation

// MARK: - VoiceTyperManager

/// Central orchestrator for the VoiceTyper app. Manages the complete
/// lifecycle of a voice-typing session: hotkey detection → audio capture
/// → transcription → text insertion.
@MainActor
final class VoiceTyperManager {

    // MARK: - Dependencies

    /// The shared application state observed by the UI.
    private let appState: AppState

    // MARK: - Subsystems

    /// Global hotkey monitor for Option-key hold detection.
    private var hotkeyMonitor: HotkeyMonitor?

    /// Audio capture engine (16 kHz mono Float32).
    private var audioEngine: AudioEngine?

    /// The active transcription engine (Whisper or Apple Speech).
    private var transcriptionEngine: (any TranscriptionEngine)?

    /// Text insertion engine (AX API primary, clipboard fallback).
    private let textInserter = TextInserter()

    /// Floating HUD overlay controller for waveform and live text.
    private var overlayController: OverlayWindowController?

    // MARK: - Silence Detection

    /// Duration (seconds) of continuous silence required to auto-stop.
    private let silenceTimeout: TimeInterval = 3.0

    /// Amplitude threshold below which audio is considered silence.
    private let silenceAmplitudeThreshold: Float = 0.01

    /// Timestamp when amplitude last exceeded the silence threshold.
    private var lastNonSilentTime: Date = .distantPast

    /// Timer that periodically checks for prolonged silence.
    private var silenceTimer: Timer?

    // MARK: - Session Timing

    /// Timestamp when recording stopped, used to compute latency.
    private var processingStartTime: Date?

    // MARK: - Initialisation

    /// Creates a new VoiceTyperManager.
    ///
    /// - Parameter appState: The shared application state. The manager
    ///   reads settings from and writes status updates to this object.
    init(appState: AppState) {
        self.appState = appState
    }

    /// Timer that polls for Accessibility permission to be granted,
    /// so the hotkey monitor can be restarted without relaunching.
    private var accessibilityPollTimer: Timer?

    // MARK: - Public API

    /// Starts the VoiceTyper system.
    ///
    /// Sets up the hotkey monitor and selects the appropriate transcription
    /// engine based on model availability and user settings.
    func start() {
        // Select the transcription engine.
        selectEngine()

        // Create and start the hotkey monitor.
        let monitor = HotkeyMonitor(
            holdThreshold: appState.holdThreshold
        )
        monitor.onRecordingStart = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }
        monitor.onRecordingStop = { [weak self] in
            Task { @MainActor in
                self?.stopRecording()
            }
        }
        monitor.start()
        self.hotkeyMonitor = monitor

        // If the event tap failed (no Accessibility permission yet),
        // start a polling timer to retry once permission is granted.
        if monitor.needsRestart {
            startAccessibilityPolling()
        }

        // Create the overlay controller.
        self.overlayController = OverlayWindowController(appState: appState)

        appState.currentState = .idle
    }

    // MARK: - Accessibility Polling

    /// Starts a repeating timer that checks whether Accessibility
    /// permission has been granted. Once granted, restarts the hotkey
    /// monitor's event tap and stops polling.
    private func startAccessibilityPolling() {
        // Invalidate any existing timer first.
        accessibilityPollTimer?.invalidate()

        accessibilityPollTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }
                self.hotkeyMonitor?.restartIfNeeded()

                // If the monitor is now running, stop polling.
                if self.hotkeyMonitor?.isRunning == true {
                    timer.invalidate()
                    self.accessibilityPollTimer = nil
                    print("[VoiceTyperManager] ✅ Hotkey monitor started successfully after permission grant.")
                }
            }
        }
    }

    /// Stops the VoiceTyper system and releases all resources.
    func stop() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil

        hotkeyMonitor?.stop()
        hotkeyMonitor = nil

        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine?.stopRecording()
        audioEngine = nil

        overlayController?.hideOverlay()
        overlayController = nil

        appState.currentState = .disabled
    }

    // MARK: - Engine Selection

    /// Selects the transcription engine based on model availability
    /// and user preferences.
    ///
    /// Priority:
    /// 1. If Whisper model is downloaded (and user hasn't forced Apple
    ///    Speech) → WhisperEngine.
    /// 2. Otherwise → AppleSpeechEngine as fallback.
    private func selectEngine() {
        if !appState.useAppleSpeechFallback,
           appState.isModelDownloaded,
           let modelPath = appState.modelFilePath {
            transcriptionEngine = WhisperEngine(modelPath: modelPath.path)
        } else {
            // Whisper model not available or user prefers Apple Speech.
            transcriptionEngine = AppleSpeechEngine()
        }
    }

    // MARK: - Recording Lifecycle

    /// Begins a voice-typing recording session.
    ///
    /// Called when the hotkey hold threshold is exceeded. Sets up audio
    /// capture, shows the overlay, and starts silence detection.
    private func startRecording() {
        guard appState.isEnabled,
              appState.currentState == .idle else {
            return
        }

        // Re-select engine each session so that model downloads or
        // setting changes take effect without requiring an app restart.
        selectEngine()

        appState.currentState = .recording
        appState.partialTranscription = ""
        appState.currentAmplitude = 0.0

        // Play start sound.
        playSound(.start)

        // Show the overlay if enabled.
        if appState.showOverlay {
            overlayController?.showOverlay()
        }

        // Set up and start audio capture.
        let engine = AudioEngine()
        engine.onAmplitudeUpdate = { [weak self] amplitude in
            Task { @MainActor in
                self?.handleAmplitudeUpdate(amplitude)
            }
        }
        do {
            engine.startRecording()
            self.audioEngine = engine
        } catch {
            // Audio engine failed to start — abort the session.
            appState.currentState = .idle
            overlayController?.hideOverlay()
            return
        }

        // Start silence detection.
        lastNonSilentTime = Date()
        startSilenceDetection()
    }

    /// Stops recording and triggers transcription.
    ///
    /// Called when the hotkey is released or silence is detected.
    private func stopRecording() {
        guard appState.currentState == .recording else { return }

        // Stop silence detection.
        silenceTimer?.invalidate()
        silenceTimer = nil

        // Stop audio capture and retrieve samples.
        guard let engine = audioEngine else {
            appState.currentState = .idle
            return
        }
        let samples = engine.stopRecording()
        self.audioEngine = nil

        // Record when processing started (for latency calculation).
        processingStartTime = Date()

        // Transition to processing state.
        appState.currentState = .processing
        appState.currentAmplitude = 0.0

        // Play stop sound.
        playSound(.stop)

        // Guard against empty audio.
        guard !samples.isEmpty else {
            finishSession(transcription: nil)
            return
        }

        // Run transcription asynchronously.
        Task {
            await runTranscription(samples: samples)
        }
    }

    // MARK: - Transcription

    /// Runs the transcription engine on the captured audio samples.
    ///
    /// - Parameter samples: 16 kHz mono Float32 PCM audio data.
    private func runTranscription(samples: [Float]) async {
        guard let engine = transcriptionEngine else {
            finishSession(transcription: nil)
            return
        }

        let rawText = await engine.transcribe(samples: samples)

        // Apply smart punctuation post-processing.
        let processedText = rawText.map { smartPunctuation($0) }

        await MainActor.run {
            finishSession(transcription: processedText)
        }
    }

    // MARK: - Session Completion

    /// Completes a voice-typing session: inserts text, updates stats,
    /// and returns to idle.
    ///
    /// - Parameter transcription: The final transcribed text, or `nil`
    ///   if transcription failed or produced no output.
    private func finishSession(transcription: String?) {
        if let text = transcription, !text.isEmpty {
            // Transition to inserting state.
            appState.currentState = .inserting
            appState.lastTranscription = text

            // Insert the text into the focused field.
            textInserter.insertText(text)

            // Calculate and record session statistics.
            let wordCount = text.split(separator: " ").count
            let latency: TimeInterval
            if let start = processingStartTime {
                latency = Date().timeIntervalSince(start)
            } else {
                latency = 0
            }
            appState.recordSession(words: wordCount, latency: latency)

            // Play completion sound.
            playSound(.complete)
        }

        processingStartTime = nil

        // Hide the overlay after a brief delay so the user can see
        // the final transcription.
        let overlayRef = overlayController
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            overlayRef?.hideOverlay()
        }

        appState.currentState = .idle
    }

    // MARK: - Silence Detection

    /// Starts a repeating timer that checks whether audio has been
    /// silent for longer than the silence timeout.
    private func startSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkSilence()
            }
        }
    }

    /// Evaluates whether the microphone has been silent long enough
    /// to auto-stop recording.
    private func checkSilence() {
        guard appState.currentState == .recording else {
            silenceTimer?.invalidate()
            silenceTimer = nil
            return
        }

        let elapsed = Date().timeIntervalSince(lastNonSilentTime)
        if elapsed >= silenceTimeout {
            // Silence detected for too long — auto-stop.
            stopRecording()
        }
    }

    /// Handles amplitude updates from the audio engine.
    ///
    /// Updates the app state for waveform visualisation and tracks
    /// the last time non-silent audio was detected.
    ///
    /// - Parameter amplitude: The current RMS amplitude (0.0–1.0).
    private func handleAmplitudeUpdate(_ amplitude: Float) {
        appState.currentAmplitude = amplitude

        if amplitude > silenceAmplitudeThreshold {
            lastNonSilentTime = Date()
        }
    }

    // MARK: - Smart Punctuation

    /// Applies basic punctuation post-processing to transcribed text.
    ///
    /// Rules:
    /// - Capitalises the first character.
    /// - Appends a period if the text doesn't end with sentence-ending
    ///   punctuation (. ! ? … ).
    /// - Trims leading/trailing whitespace.
    ///
    /// - Parameter text: Raw transcription output.
    /// - Returns: The text with smart punctuation applied.
    private func smartPunctuation(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        // Capitalise the first character.
        let first = result.prefix(1).uppercased()
        result = first + result.dropFirst()

        // Add a period if the text doesn't end with terminal punctuation.
        let terminalPunctuation: Set<Character> = [".", "!", "?", "…"]
        if let lastChar = result.last,
           !terminalPunctuation.contains(lastChar) {
            result.append(".")
        }

        return result
    }

    // MARK: - Sound Effects

    /// The types of sound effects played during a session.
    private enum SoundEffect {
        /// Played when recording starts.
        case start
        /// Played when recording stops.
        case stop
        /// Played when text is successfully inserted.
        case complete
    }

    /// Plays a system sound effect if sound effects are enabled in settings.
    ///
    /// Uses built-in macOS system sounds:
    /// - Start: "Tink" (subtle tap)
    /// - Stop: "Pop" (gentle pop)
    /// - Complete: "Purr" (soft confirmation)
    ///
    /// - Parameter effect: The sound effect to play.
    private func playSound(_ effect: SoundEffect) {
        guard appState.playSoundEffects else { return }

        let soundName: String
        switch effect {
        case .start:
            soundName = "Tink"
        case .stop:
            soundName = "Pop"
        case .complete:
            soundName = "Purr"
        }

        // NSSound can locate system sounds by name.
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        }
    }
}
