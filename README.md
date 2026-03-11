# VoiceNative

Local, real-time voice-to-text for macOS. Press a key, speak, and the transcription appears at your cursor. No cloud, no latency, no subscriptions.

## How It Works

```
Right Shift → Speak → Right Shift → Text pasted at cursor
```

VoiceNative sits in your menu bar. When you press Right Shift, it captures audio from your microphone, transcribes it locally using WhisperKit (Apple's CoreML-optimized Whisper), and pastes the result directly into whatever app you're working in.

Everything runs on-device. Audio never leaves your Mac.

## Features

- **Global hotkey** (Right Shift) toggles recording from any app
- **Auto-paste** transcription at the active cursor position
- **Menu bar waveform** shows live recording status
- **Streaming pipeline** transcribes in 30-second chunks while you're still speaking
- **100% local** -- no network requests after initial model download
- **Hardware accelerated** via Apple Neural Engine and CoreML

## Architecture

```
VoiceNativeApp (SwiftUI MenuBarExtra)
├── AppState              State machine: idle → loading → ready → listening → processing
├── AudioCaptureService   AVAudioEngine, 48kHz native → 16kHz mono via AVAudioConverter
├── TranscriptionService  WhisperKit, CoreML, ANE-optimized model loading + inference
├── HotkeyService         NSEvent global + local monitors for Right Shift detection
├── TextInjectionService  NSPasteboard + CGEvent (Cmd+V) to paste into frontmost app
├── VADService            Energy-based voice activity detection
└── SoundFeedback         Subtle audio cues (Tink for start, Submarine for completion)
```

### Recording Pipeline

1. **Capture**: AVAudioEngine records at the mic's native sample rate (typically 48kHz)
2. **Resample**: AVAudioConverter downsamples to 16kHz mono Float32 (Whisper's input format)
3. **Normalize**: vDSP peak normalization via Accelerate framework
4. **Stream**: Background pipeline transcribes 30s chunks in parallel with recording
5. **Finalize**: On stop, only the remaining audio tail needs transcription
6. **Inject**: Text is copied to clipboard and Cmd+V is simulated into the source app

### Model Loading

- First launch: downloads `openai_whisper-large-v3_turbo_955MB` from Hugging Face (~950MB)
- CoreML compiles for the Neural Engine on first run (~60-90s one-time cost)
- Subsequent launches load from cache in ~5 seconds
- Keepalive timer prewarms the model every 2 minutes to prevent unload

## Performance

| Metric | Target | Achieved |
|--------|--------|----------|
| Model load (cached) | < 10s | ~5s |
| Real-time factor (RTF) | < 0.5 | ~0.3 |
| Memory (idle) | < 200MB | ~150MB |
| Binary size | minimal | 6MB |

### Hardware Acceleration

VoiceNative runs the Whisper encoder on Apple's **Neural Engine (ANE)** via CoreML, which is significantly faster than CPU-only inference. The text decoder runs on CPU + ANE combined. This is configured via `ModelComputeOptions`:

```swift
ModelComputeOptions(
    audioEncoderCompute: .cpuAndNeuralEngine,
    textDecoderCompute: .cpuAndNeuralEngine
)
```

The model uses quantized weights (`large-v3-turbo`) to reduce memory footprint while maintaining transcription quality.

## Installation

### From DMG

1. Download `VoiceNative.dmg` from the dist folder (or build it yourself)
2. Open the DMG, drag VoiceNative to Applications
3. Launch from Applications
4. Grant permissions when prompted (Microphone, Accessibility)

### Build from Source

Requires macOS 15 (Sequoia) and Xcode 16+.

```bash
git clone <repo-url>
cd macvoice

# Debug build + run
make run

# Release .app bundle
make app
# Output: dist/VoiceNative.app

# Release .app + DMG installer
make dmg
# Output: dist/VoiceNative.dmg
```

## Usage

### Recording

| Action | Method |
|--------|--------|
| Start recording | Press **Right Shift** or click mic icon in menu bar |
| Stop + transcribe | Press **Right Shift** again or click stop icon |
| Cancel recording | Press **Escape** |

After transcription completes, the text is automatically pasted at your cursor position and copied to the clipboard.

### Menu Bar

The menu bar icon reflects the current state:

| Icon | State |
|------|-------|
| `mic` | Ready (green dot) |
| `▮▮▮▮▮` (animated bars) | Recording |
| `⋯` (spinning) | Processing |
| `↓` (pulsing) | Loading model |
| `✓` | Transcription copied |

Click the menu bar icon to see the popover with record/stop controls, copy last transcription, and access history and settings.

### Settings

- **Trigger Mode**: Toggle (press to start/stop) or Hold-to-Talk
- **Model Selection**: Choose Whisper model variant
- **VAD Sensitivity**: Low / Medium / High (active in Hold-to-Talk mode)
- **Silence Timeout**: Auto-stop after silence (1-5 seconds)
- **Auto-Paste**: Toggle automatic Cmd+V after transcription
- **Custom Dictionary**: Add technical terms for better recognition
- **Sound Feedback**: Toggle audio cues

## Permissions

VoiceNative needs two macOS permissions:

1. **Microphone** -- to capture audio for transcription
2. **Accessibility** -- to simulate Cmd+V paste and detect the global hotkey

Grant these in System Settings > Privacy & Security when prompted on first launch.

## Technical Decisions

**Why WhisperKit over whisper.cpp?** WhisperKit is Apple's first-party CoreML integration for Whisper, purpose-built for ANE acceleration on Apple Silicon. It ships as a Swift package with native CoreML model compilation.

**Why NSEvent monitors over CGEventTap?** CGEventTap requires Input Monitoring permission and can silently fail when the app's own windows have focus. NSEvent global + local monitors (a proven pattern for macOS menu bar apps) cover both other-app and own-app events with just Accessibility permission.

**Why a streaming pipeline?** For long recordings (> 30s), waiting until the end to transcribe adds noticeable delay. The streaming pipeline transcribes 30-second chunks in the background while recording continues, so only the final tail needs processing when you stop.

**Why no cloud?** Privacy. Voice data is sensitive. Every API call is a liability. Local inference on Apple Silicon is fast enough for real-time transcription.

## Project Structure

```
macvoice/
├── VoiceNative/
│   ├── Package.swift
│   ├── Resources/
│   │   ├── Info.plist
│   │   └── VoiceNative.entitlements
│   └── Sources/VoiceNative/
│       ├── App/
│       │   ├── VoiceNativeApp.swift       Entry point, MenuBarExtra
│       │   └── AppState.swift             Central state machine
│       ├── Services/
│       │   ├── AudioCaptureService.swift  Mic recording + resampling
│       │   ├── TranscriptionService.swift WhisperKit integration
│       │   ├── HotkeyService.swift        Global hotkey handling
│       │   ├── TextInjectionService.swift Clipboard + paste
│       │   └── VADService.swift           Voice activity detection
│       ├── Views/
│       │   ├── MenuBarPopover.swift       Minimal popover UI
│       │   ├── SettingsView.swift         Settings tabs
│       │   ├── HistoryView.swift          Transcription history
│       │   └── OnboardingView.swift       First-run setup
│       ├── Config/
│       │   └── TechnicalDictionary.swift  Engineering vocabulary
│       └── Utilities/
│           ├── Constants.swift
│           ├── SoundFeedback.swift
│           ├── LaunchAtLogin.swift
│           └── PermissionManager.swift
├── scripts/
│   ├── package-app.sh                    Build .app bundle
│   └── create-dmg.sh                     Create DMG installer
├── Makefile
└── README.md
```

## License

MIT
