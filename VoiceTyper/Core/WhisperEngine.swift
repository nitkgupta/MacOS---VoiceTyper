import Foundation
import Accelerate

/// Wrapper for the whisper.cpp C API.
final class WhisperEngine: TranscriptionEngine, @unchecked Sendable {
    
    private var ctx: OpaquePointer?
    let isModelLoaded: Bool
    
    /// The default expected location for the Whisper model.
    static var modelPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("VoiceTyper")
        let modelsDir = appDir.appendingPathComponent("models")
        return modelsDir.appendingPathComponent("ggml-medium.bin").path
    }
    
    /// Checks if the model exists at the expected path.
    static func modelExists() -> Bool {
        return FileManager.default.fileExists(atPath: modelPath)
    }
    
    init(modelPath: String) {
        // Stub implementation until whisper.cpp is fully integrated
        self.ctx = nil
        self.isModelLoaded = true
        
        // Real implementation:
        // self.ctx = whisper_init_from_file(modelPath)
        // self.isModelLoaded = (self.ctx != nil)
    }
    
    deinit {
        // Real implementation:
        // if let context = ctx { whisper_free(context) }
    }
    
    func transcribe(samples: [Float]) async -> String? {
        guard isModelLoaded else { return nil }
        
        return await Task.detached(priority: .userInitiated) {
            // STUB IMPLEMENTATION
            try? await Task.sleep(nanoseconds: UInt64(1.5 * 1_000_000_000))
            return "This is a simulated transcription from Whisper. The C++ library is not fully linked yet!"
            
            // Real implementation:
            /*
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.language = "auto"
            params.translate = false
            params.no_timestamps = true
            params.n_threads = Int32(max(4, ProcessInfo.processInfo.activeProcessorCount / 2))
            
            let ret = whisper_full(self.ctx, params, samples, Int32(samples.count))
            if ret != 0 { return nil }
            
            let n_segments = whisper_full_n_segments(self.ctx)
            var result = ""
            for i in 0..<n_segments {
                if let text = whisper_full_get_segment_text(self.ctx, i) {
                    result += String(cString: text)
                }
            }
            return result
            */
        }.value
    }
}

/// Utility for detecting silence in an audio buffer.
struct SilenceDetector {
    /// Returns true if the RMS of the samples is below the threshold.
    static func isSilence(_ samples: [Float], threshold: Float = 0.01) -> Bool {
        guard !samples.isEmpty else { return true }
        var sumOfSquares: Float = 0.0
        vDSP_svesq(samples, 1, &sumOfSquares, vDSP_Length(samples.count))
        let rms = sqrt(sumOfSquares / Float(samples.count))
        return rms < threshold
    }
}
