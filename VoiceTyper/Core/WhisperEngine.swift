import Foundation
import SwiftWhisper

/// Wrapper for the SwiftWhisper package.
final class WhisperEngine: TranscriptionEngine, @unchecked Sendable {
    
    private let whisper: Whisper?
    let isModelLoaded: Bool
    
    /// The default expected location for the Whisper model.
    static var modelPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("VoiceTyper")
        let modelsDir = appDir.appendingPathComponent("models")
        return modelsDir.appendingPathComponent("ggml-base.bin").path
    }
    
    /// Checks if the model exists at the expected path.
    static func modelExists() -> Bool {
        return FileManager.default.fileExists(atPath: modelPath)
    }
    
    init(modelPath: String) {
        let url = URL(fileURLWithPath: modelPath)
        // Ensure params suppress timestamps for dictation
        // Note: SwiftWhisper uses default parameters internally if we just call Whisper(fromFileURL:)
        self.whisper = Whisper(fromFileURL: url)
        self.isModelLoaded = (self.whisper != nil)
        
        if !self.isModelLoaded {
            print("[WhisperEngine] Failed to initialize whisper context from \(modelPath)")
        } else {
            // SwiftWhisper params can be set directly on the `params` property
            // We omit setting language to let it default to auto-detect for multilingual support.
            self.whisper?.params.entropy_thold = 2.4
        }
    }
    
    deinit {
        // SwiftWhisper handles cleanup internally
    }
    
    func transcribe(samples: [Float]) async -> String? {
        guard let whisper = whisper else { return nil }
        
        do {
            let segments = try await whisper.transcribe(audioFrames: samples)
            let result = segments.map(\.text).joined()
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[WhisperEngine] Transcription error: \(error)")
            return nil
        }
    }
}
