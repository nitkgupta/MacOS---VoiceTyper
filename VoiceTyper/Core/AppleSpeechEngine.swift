// MARK: - AppleSpeechEngine.swift
// VoiceTyper — macOS Menu Bar Speech-to-Text
//
// Fallback transcription engine using Apple's on-device SFSpeechRecognizer.
// Conforms to the `TranscriptionEngine` protocol so it can be swapped in
// seamlessly when the Whisper model is unavailable.
//
// Key design points:
//   • requiresOnDeviceRecognition = true  — zero network calls.
//   • Accepts raw Float32 PCM samples at 16 kHz mono (same format the
//     AudioEngine produces).
//   • Converts samples into an AVAudioPCMBuffer for the recognition
//     request.
//   • Returns the single best transcription string, or nil on failure.
//
// Privacy:
//   Everything runs locally. No audio leaves the device.
//   Nothing is logged to disk.
//
// Copyright © 2026 VoiceTyper. All rights reserved.

import AVFoundation
import Speech

// MARK: - TranscriptionEngine Protocol

/// Common interface shared by `WhisperEngine` and `AppleSpeechEngine`.
/// Any engine that can turn an array of Float32 PCM samples into text
/// conforms to this protocol.
protocol TranscriptionEngine: Sendable {
    /// Transcribe the given 16 kHz mono Float32 samples into text.
    ///
    /// - Parameter samples: PCM audio samples (16 kHz, mono, Float32).
    /// - Returns: The transcribed string, or `nil` if transcription failed.
    func transcribe(samples: [Float]) async -> String?
}

// MARK: - AppleSpeechEngine

/// On-device speech-to-text engine backed by Apple's Speech framework.
///
/// This engine is used as a fallback when the Whisper model has not been
/// downloaded or when the user explicitly selects Apple Speech in settings.
///
/// Usage:
/// ```swift
/// let engine = AppleSpeechEngine()
/// let text = await engine.transcribe(samples: audioSamples)
/// ```
final class AppleSpeechEngine: TranscriptionEngine, @unchecked Sendable {

    // MARK: - Constants

    /// The sample rate expected by this engine and produced by AudioEngine.
    private static let sampleRate: Double = 16_000

    /// Number of audio channels (mono).
    private static let channelCount: AVAudioChannelCount = 1

    // MARK: - Properties

    /// The underlying speech recogniser, configured for the current locale.
    private let recognizer: SFSpeechRecognizer?

    // MARK: - Initialisation

    /// Creates a new AppleSpeechEngine.
    ///
    /// - Parameter locale: The locale to use for recognition. Defaults to
    ///   `Locale.current` which matches the system language.
    init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.recognizer?.defaultTaskHint = .dictation
    }

    // MARK: - Availability

    /// Checks whether on-device speech recognition is available on this
    /// system. Returns `false` if:
    /// - The recogniser could not be created for the current locale.
    /// - The recogniser reports itself as unavailable.
    /// - On-device recognition is not supported (older OS / missing model).
    static func isAvailable() -> Bool {
        guard let recognizer = SFSpeechRecognizer() else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

    // MARK: - Authorization

    /// Requests speech recognition authorization from the user.
    ///
    /// - Returns: `true` if authorization was granted, `false` otherwise.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - TranscriptionEngine Conformance

    /// Transcribes the given PCM samples using Apple's on-device speech
    /// recognition.
    ///
    /// The method converts the raw Float32 array into an `AVAudioPCMBuffer`,
    /// feeds it to an `SFSpeechAudioBufferRecognitionRequest`, and waits
    /// for the final result.
    ///
    /// - Parameter samples: 16 kHz mono Float32 PCM audio samples.
    /// - Returns: The best transcription string, or `nil` on failure.
    func transcribe(samples: [Float]) async -> String? {
        guard let recognizer = recognizer,
              recognizer.isAvailable else {
            return nil
        }

        // Convert the Float array into an AVAudioPCMBuffer.
        guard let buffer = createPCMBuffer(from: samples) else {
            return nil
        }

        // Create and configure the recognition request.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        // Feed the audio buffer to the request and signal end of audio.
        request.append(buffer)
        request.endAudio()

        // Run recognition and return the best transcription.
        return await performRecognition(recognizer: recognizer, request: request)
    }

    // MARK: - Private Helpers

    /// Converts an array of Float32 samples into an `AVAudioPCMBuffer`
    /// at 16 kHz mono.
    ///
    /// - Parameter samples: Raw PCM samples.
    /// - Returns: A populated `AVAudioPCMBuffer`, or `nil` if creation fails.
    private func createPCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty else { return nil }

        // Define the audio format: 16 kHz, mono, Float32, non-interleaved.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: Self.channelCount,
            interleaved: false
        ) else {
            return nil
        }

        // Allocate the buffer with the required frame capacity.
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return nil
        }

        // Copy sample data into the buffer's float channel data.
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return nil }
        samples.withUnsafeBufferPointer { sourcePointer in
            guard let baseAddress = sourcePointer.baseAddress else { return }
            channelData[0].update(from: baseAddress, count: samples.count)
        }

        return buffer
    }

    /// Performs the actual speech recognition task asynchronously.
    ///
    /// - Parameters:
    ///   - recognizer: The configured `SFSpeechRecognizer`.
    ///   - request: The audio buffer recognition request.
    /// - Returns: The best transcription string, or `nil`.
    private func performRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest
    ) async -> String? {
        await withCheckedContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                // We only care about the final result.
                guard let result = result else {
                    if error != nil {
                        continuation.resume(returning: nil)
                    }
                    // If both are nil, keep waiting — the framework will
                    // call back again with either a result or an error.
                    return
                }

                if result.isFinal {
                    let transcription = result.bestTranscription.formattedString
                    let trimmed = transcription.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    continuation.resume(
                        returning: trimmed.isEmpty ? nil : trimmed
                    )
                }
            }
        }
    }
}
