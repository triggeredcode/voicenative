# VoiceNative

Local voice-to-text for macOS. Press a key, speak, release. Text appears at your cursor. No cloud, no latency, no subscription.

## Install

Download `VoiceNative.dmg` from [Releases](../../releases), open it, drag to Applications. On first launch, grant Microphone and Accessibility permissions when prompted.

Or build from source (macOS 15+, Xcode 16+):

```bash
git clone https://github.com/user/voicenative.git
cd voicenative
make dmg
```

## How It Works

```
Right Shift → speak → Right Shift → text pasted at cursor
```

VoiceNative lives in your menu bar. It captures audio, transcribes locally using WhisperKit on Apple's Neural Engine, and pastes the result into whatever app you're working in. Audio never leaves your Mac.

## What to Expect

**First launch** downloads the Whisper model (~950 MB) and compiles it for the Neural Engine (~60–90 seconds). This is a one-time cost. Subsequent launches load in ~5 seconds.

**Recording limit** is 5 minutes by default. For recordings over 30 seconds, a background pipeline transcribes in 30-second chunks while you speak — only the final tail needs processing when you stop.

**Transcription speed**: real-time factor ~0.3 (a 10-second recording transcribes in ~3 seconds).

**Memory**: ~150 MB idle. The model stays warm via micro-inference every 2 minutes to prevent the Neural Engine from unloading it.

## Usage

| Action | Method |
|--------|--------|
| Start recording | **Right Shift** or click menu bar icon |
| Stop + transcribe | **Right Shift** again |
| Cancel | **Escape** |

Text is pasted at your cursor and copied to the clipboard.

### Settings

Trigger mode (toggle or hold-to-talk), model selection, VAD sensitivity, silence timeout, auto-paste, custom dictionary, sound feedback.

## Permissions

1. **Microphone** — audio capture
2. **Accessibility** — global hotkey detection and Cmd+V paste simulation

System Settings → Privacy & Security.

## Architecture

```
VoiceNativeApp (SwiftUI MenuBarExtra)
├── AppState              idle → loading → ready → listening → processing
├── AudioCaptureService   AVAudioEngine 48kHz → 16kHz mono via AVAudioConverter
├── TranscriptionService  WhisperKit, CoreML, Neural Engine
├── HotkeyService         NSEvent global + local monitors
├── TextInjectionService  NSPasteboard + CGEvent (Cmd+V)
├── VADService            Energy-based voice activity detection
└── SoundFeedback         Audio cues (start, stop, copied, error)
```

### Pipeline

1. Capture at mic's native rate (48kHz)
2. Resample to 16kHz mono Float32
3. Normalize via vDSP (Accelerate framework)
4. Stream 30s chunks to WhisperKit in background
5. On stop, transcribe remaining tail
6. Paste into frontmost app

### Key Decisions

**WhisperKit over whisper.cpp** — Apple's CoreML integration for Whisper, purpose-built for Neural Engine acceleration on Apple Silicon.

**NSEvent monitors over CGEventTap** — CGEventTap requires Input Monitoring permission and silently fails when the app's own windows have focus. NSEvent monitors need only Accessibility permission.

**Streaming pipeline** — waiting until the end of a long recording to transcribe adds delay. Chunking in the background means only the tail needs processing on stop.

**No cloud** — voice data is sensitive. Local inference on Apple Silicon is fast enough.

## License

MIT
