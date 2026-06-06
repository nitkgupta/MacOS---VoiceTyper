// MARK: - AudioEngine.swift
// VoiceTyper — macOS Menu Bar Speech-to-Text
//
// Captures microphone audio using AVAudioEngine, converts it to the
// format required by Whisper (16 kHz, mono, Float32), and accumulates
// samples in a thread-safe in-memory ring buffer.
//
// Key design points:
//   • Audio is NEVER written to disk — samples live only in RAM.
//   • The ring buffer has a maximum capacity of 30 seconds at 16 kHz
//     (480,000 samples). Older samples are discarded when full.
//   • A serial DispatchQueue (`bufferQueue`) guards all buffer access
//     for thread safety, since the tap callback runs on a realtime
//     audio thread.
//   • `currentAmplitude` is updated with the RMS of each incoming
//     buffer for waveform visualisation in the UI.
//   • `stopRecording()` returns the accumulated samples and resets
//     the buffer, ready for the next session.
//
// Audio pipeline:
//   ┌──────────┐    hardware    ┌───────────────┐    16kHz mono    ┌────────┐
//   │   Mic    │──── format ───▶│ AVAudioConverter│──── Float32 ──▶│ Buffer │
//   └──────────┘               └───────────────┘                 └────────┘
//
// Privacy:
//   Nothing is logged to disk. No network calls. Audio stays in RAM.
//
// Copyright © 2026 VoiceTyper. All rights reserved.

import AVFoundation
import Observation

// MARK: - AudioEngine

/// Captures and accumulates microphone audio in the format Whisper
/// expects: 16 kHz, mono, Float32 PCM.
///
/// Usage:
/// ```swift
/// let engine = AudioEngine()
/// engine.requestMicrophonePermission { granted in
///     guard granted else { return }
///     engine.startRecording()
///     // ... later ...
///     let samples = engine.stopRecording()
///     let text = await whisperEngine.transcribe(samples: samples)
/// }
/// ```

final class AudioEngine {

    // MARK: - Constants

    /// Target sample rate for Whisper input.
    private static let targetSampleRate: Double = 16_000

    /// Number of audio channels (mono).
    private static let targetChannels: AVAudioChannelCount = 1

    /// Maximum buffer duration in seconds. Audio beyond this is
    /// discarded from the front of the buffer (oldest samples first).
    private static let maxBufferDuration: TimeInterval = 30.0

    /// Maximum number of samples retained in the buffer.
    /// 30 seconds × 16,000 Hz = 480,000 samples.
    private static let maxBufferSamples: Int = Int(targetSampleRate * maxBufferDuration)

    /// Size of the tap buffer in frames. 4096 frames at 16 kHz ≈ 256 ms
    /// per callback — a good balance between latency and overhead.
    private static let tapBufferSize: AVAudioFrameCount = 4096

    // MARK: - Observable Properties

    /// Current microphone amplitude (RMS), normalised to roughly 0.0–1.0.
    /// Updated on every tap callback for waveform visualisation.
    /// Observation-tracked so SwiftUI views update automatically.
    var onAmplitudeUpdate: ((Float) -> Void)?
    private(set) var currentAmplitude: Float = 0.0

    /// Whether the engine is actively recording.
    private(set) var isRecording: Bool = false

    // MARK: - Private Properties

    /// The AVAudioEngine that manages the audio graph.
    private let audioEngine = AVAudioEngine()

    /// Converter from the hardware's native format to 16 kHz mono Float32.
    /// Created lazily when recording starts, since the hardware format
    /// is not known until the engine is configured.
    private var audioConverter: AVAudioConverter?

    /// The target audio format: 16 kHz, mono, Float32, non-interleaved.
    private let targetFormat: AVAudioFormat

    /// In-memory ring buffer accumulating converted samples.
    /// Access is guarded by `bufferQueue`.
    private var sampleBuffer: [Float] = []

    /// Serial queue protecting `sampleBuffer` from concurrent access.
    /// The tap callback runs on a realtime audio thread; all buffer
    /// reads and writes go through this queue.
    private let bufferQueue = DispatchQueue(
        label: "com.voicetyper.audioEngine.bufferQueue",
        qos: .userInteractive
    )

    // MARK: - Initialisation

    /// Creates a new AudioEngine.
    ///
    /// The target format (16 kHz mono Float32) is created here. It does
    /// not depend on hardware and is constant for the app's lifetime.
    init() {
        // Create the target format. This should always succeed for
        // standard PCM parameters.
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: false
        )!

        // Pre-allocate buffer capacity to avoid reallocations during
        // recording. We reserve the max to avoid malloc on the audio
        // thread path (the actual append still goes through bufferQueue).
        sampleBuffer.reserveCapacity(Self.maxBufferSamples)
    }

    // MARK: - Permissions

    /// Requests microphone access from the user.
    ///
    /// On macOS 14+ the system shows a permission dialog the first
    /// time this is called. Subsequent calls return the cached result.
    ///
    /// - Parameter completion: Called on the main queue with `true`
    ///   if access was granted, `false` otherwise.
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    /// Synchronously checks the current microphone authorization status.
    ///
    /// - Returns: `true` if the user has granted microphone access.
    static func isMicrophoneAuthorized() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Recording Control

    /// Starts capturing audio from the default input device.
    ///
    /// Installs a tap on the audio engine's input node, converts
    /// incoming audio to 16 kHz mono Float32, and accumulates samples
    /// in the ring buffer.
    ///
    /// Does nothing if already recording.
    func startRecording() {
        guard !isRecording else { return }

        // Clear any leftover samples from a previous session.
        bufferQueue.sync {
            sampleBuffer.removeAll(keepingCapacity: true)
        }
        currentAmplitude = 0.0

        let inputNode = audioEngine.inputNode

        // The hardware format of the input node. We must install the
        // tap in this format — AVAudioEngine does not allow format
        // conversion in the tap itself.
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // Validate the hardware format. A sample rate of 0 indicates
        // no input device.
        guard hardwareFormat.sampleRate > 0 else {
            print("[AudioEngine] ❌ No audio input device available.")
            return
        }

        // Create the converter from hardware format → target format.
        // The converter is reused for the entire recording session.
        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            print("[AudioEngine] ❌ Failed to create audio converter.")
            return
        }
        audioConverter = converter

        // Install the tap on the input node. The callback fires on a
        // realtime audio thread, so we do minimal work here and
        // dispatch buffer manipulation to `bufferQueue`.
        inputNode.installTap(
            onBus: 0,
            bufferSize: Self.tapBufferSize,
            format: hardwareFormat
        ) { [weak self] (buffer, _) in
            self?.processTapBuffer(buffer)
        }

        // Start the engine.
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("[AudioEngine] ❌ Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            audioConverter = nil
        }
    }

    /// Stops recording and returns the accumulated audio samples.
    ///
    /// The engine is stopped, the tap is removed, and the internal
    /// buffer is drained and returned. After this call, the engine is
    /// ready for another `startRecording()`.
    ///
    /// - Returns: The accumulated 16 kHz mono Float32 samples, or an
    ///   empty array if nothing was recorded.
    @discardableResult
    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        // Stop the engine and remove the tap.
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Release the converter.
        audioConverter = nil

        // Drain the buffer.
        let samples: [Float] = bufferQueue.sync {
            let captured = sampleBuffer
            sampleBuffer.removeAll(keepingCapacity: true)
            return captured
        }

        // Reset observable state.
        isRecording = false
        currentAmplitude = 0.0

        return samples
    }

    // MARK: - Audio Processing

    /// Converts a tap buffer from hardware format to 16 kHz mono
    /// Float32 and appends the result to the ring buffer.
    ///
    /// Also computes the RMS amplitude for waveform visualisation.
    ///
    /// - Parameter buffer: The PCM buffer from the input node tap,
    ///   in the hardware's native format.
    private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter else { return }

        // Estimate how many output frames we'll get after conversion.
        // ratio = targetRate / hardwareRate. Multiply by input frame
        // count and add a small margin.
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let estimatedOutputFrames = AVAudioFrameCount(
            Double(buffer.frameLength) * ratio + 1
        )

        // Allocate the output buffer in the target format.
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: estimatedOutputFrames
        ) else {
            return
        }

        // Convert the audio. The input block is called by the converter
        // to pull samples — we provide the entire tap buffer in one go.
        var inputConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError, withInputFrom: inputBlock)

        guard status != .error else {
            if let err = conversionError {
                print("[AudioEngine] ⚠️ Conversion error: \(err.localizedDescription)")
            }
            return
        }

        // Extract the Float32 samples from the converted buffer.
        let frameLength = Int(convertedBuffer.frameLength)
        guard frameLength > 0,
              let channelData = convertedBuffer.floatChannelData else {
            return
        }

        // Copy samples into a Swift array. We use channel 0 (mono).
        let samples = Array(UnsafeBufferPointer(
            start: channelData[0],
            count: frameLength
        ))

        // Compute RMS amplitude for visualisation.
        let rms = computeRMS(samples)

        // Update amplitude on the main queue since it's .
        DispatchQueue.main.async { [weak self] in
            self?.currentAmplitude = rms
            self?.onAmplitudeUpdate?(rms)
        }

        // Append to the ring buffer, trimming from the front if
        // capacity is exceeded.
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            self.sampleBuffer.append(contentsOf: samples)

            // Trim oldest samples if we exceed the maximum.
            if self.sampleBuffer.count > Self.maxBufferSamples {
                let excess = self.sampleBuffer.count - Self.maxBufferSamples
                self.sampleBuffer.removeFirst(excess)
            }
        }
    }

    // MARK: - Utility

    /// Computes the Root Mean Square (RMS) of an array of audio samples.
    ///
    /// RMS gives a good approximation of perceived loudness and is
    /// suitable for driving a waveform visualisation.
    ///
    /// - Parameter samples: Float32 PCM audio samples.
    /// - Returns: The RMS value, or 0.0 if the array is empty.
    private func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }

        // Use vDSP for efficient vectorised computation if available
        // via Accelerate. For simplicity and to avoid an extra import,
        // we do a manual loop — the buffer sizes are small enough
        // (~256 ms worth) that performance is not a concern.
        var sumOfSquares: Float = 0.0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        let meanSquare = sumOfSquares / Float(samples.count)
        return sqrtf(meanSquare)
    }
}
