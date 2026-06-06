# VoiceTyper 🎙️

VoiceTyper is a lightning-fast, privacy-first macOS menu bar app that brings seamless speech-to-text functionality to any text field on your Mac. Powered by the state-of-the-art **Whisper** model (via `whisper.cpp`), all transcription happens **100% locally on your machine**.

No cloud, no network calls, no data collection. Your voice never leaves your Mac.

## ✨ Features

- **Global Hotkey:** Simply hold down the **Option (⌥)** key to start speaking. Release it to instantly type your words into whatever app has focus.
- **Works Everywhere:** From Safari and Pages to Terminal apps like iTerm2 and Alacritty—if you can type in it, VoiceTyper can type in it.
- **Completely Local & Private:** Powered entirely by on-device processing. Not a single byte of your audio or text is sent to the internet or logged to disk.
- **Smart Punctuation:** Automatically capitalises the first letter and adds terminal punctuation (`.` or `?`) if you forget to say it.
- **Floating HUD:** A beautiful, non-intrusive floating overlay appears when recording, complete with a live waveform visualisation.
- **Apple Speech Fallback:** Don't want to download the Whisper model? VoiceTyper seamlessly falls back to Apple's built-in on-device speech recognition engine.
- **Native SwiftUI Design:** Built natively for macOS with a beautiful, dark-mode-first popover interface.

## 🚀 Installation

1. Download the latest `VoiceTyper.dmg` release.
2. Double-click the DMG to mount it.
3. Drag the **VoiceTyper** app into your `Applications` folder.
4. Open VoiceTyper from your Applications folder.

### Permissions Required
When you first run VoiceTyper, it will ask for two critical permissions:
1. **Microphone Access:** To capture your voice.
2. **Accessibility Access:** To detect the global `Option (⌥)` key hold and to simulate typing into other applications.

*Note: If you update VoiceTyper during development, macOS might require you to remove VoiceTyper from the Accessibility list in System Settings (using the `-` button) and re-add it.*

## 📖 Usage

1. **Enable the App:** Click the microphone icon in your menu bar and toggle the app to **Enabled**.
2. **Download the Model (Optional):** Click the Settings gear and download the recommended Whisper model (ggml-medium.bin). If you skip this, it will fall back to Apple Speech.
3. **Speak:** Click into any text field, document, or terminal window.
4. **Hold Option (⌥):** Press and hold the Option key. You will hear a soft "Tink" sound and see the floating waveform overlay.
5. **Release:** Release the key when you are done speaking. Your Mac will process the audio and type it out for you instantly!

## ⚙️ Settings & Customisation

Click the gear icon in the menu bar popover to customise VoiceTyper:
- **Hold Threshold:** Adjust how long you need to hold the Option key before recording begins (0.5s – 3.0s).
- **Language:** Force a specific language, or leave it on "Auto-detect" for the Whisper engine to figure it out automatically.
- **Live Preview Overlay:** Toggle the floating waveform HUD.
- **Sound Effects:** Toggle the start/stop chimes.
- **Launch at Login:** Have VoiceTyper automatically start when you boot your Mac.

## 🛠️ Built With

- **[SwiftUI](https://developer.apple.com/xcode/swiftui/)** for the user interface.
- **[AVFoundation](https://developer.apple.com/documentation/avfoundation)** for high-performance audio capture.
- **[whisper.cpp](https://github.com/ggerganov/whisper.cpp)** for the core transcription engine.
- **[SFSpeechRecognizer](https://developer.apple.com/documentation/speech)** for the Apple Speech fallback engine.

## 🛡️ Privacy Commitment

VoiceTyper was built from the ground up to respect your privacy. 
- The app has App Transport Security rules that block arbitrary network loads.
- Audio buffers are held strictly in memory and are immediately discarded after processing.
- Session statistics (words typed, latency) are kept in RAM and reset every time you quit the app.

---

**VoiceTyper** — Voice to text, locally.
