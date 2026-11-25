# AudioNexus

AudioNexus is a Swift 6 package for reusable, privacy-oriented audio foundations
in Apple-platform applications. It captures microphone audio, normalizes it to
transcription-ready PCM, safely stages temporary WAV recordings, defines a
local-transcription boundary, and manages integrity-checked model files.

The package is intentionally not a complete transcription or meeting-notes
product. It does not currently include Whisper inference, RNNoise,
ScreenCaptureKit system-audio capture, speech synthesis, transcript storage, or
application UI.

## Platform support

- Apple Silicon (arm64) hosts and devices
- macOS 27 or later
- iOS 27 or later
- Swift 6 with the current stable Xcode

The declared package deployment targets are macOS 27 and iOS 27. Apple
frameworks used by capture (`AVFoundation`/`AVFAudio`) make the capture product
Apple-only. Device and current-Xcode verification is still outstanding; see
[Verification](#verification).

## Products and architecture

The products form one-way dependency layers:

```text
AudioNexusCore
    ↑              ↑
AudioNexusCapture  AudioNexusTranscription
```

- **`AudioNexusCore`** — platform-neutral `AudioPCMFormat` and `AudioFrame`
  values. The canonical transcription format is little-endian signed 16-bit,
  16 kHz, mono PCM.
- **`AudioNexusCapture`** — microphone permission, `AVAudioEngine` capture,
  format conversion, ordered frame events, interruption/route events, and
  temporary PCM WAV recording.
- **`AudioNexusTranscription`** — language/request/result types,
  `SpeechTranscribing`, and verified model storage. It provides no inference
  implementation.

Capture and transcription are separate products so a host links only what it
uses. The package has no third-party dependencies.

## Capture API and lifecycle

`MicrophoneCaptureService` is an actor. Subscribe before starting so state and
frame events are not missed:

```swift
import AudioNexusCapture

let capture = MicrophoneCaptureService()
let events = await capture.events()

let eventTask = Task {
    for await event in events {
        switch event {
        case let .frame(frame):
            // Hand off promptly; do not block audio processing.
            print("\(frame.sequenceNumber): \(frame.frameCount) frames")
        case let .stateChanged(state):
            print("Capture state: \(state)")
        case let .interruption(interruption):
            print("Interruption: \(interruption)")
        case .routeChanged:
            print("Audio route changed")
        case let .failed(error):
            print("Capture failed: \(error)")
        }
    }
}

try await capture.start() // Uses AudioCaptureConfiguration.transcription.

// Later:
await capture.stop()
eventTask.cancel()
```

The stream buffers the newest 64 events. If a consumer falls behind, older
pending events—including frames—can be dropped. Move frame work off the event
loop promptly.

The capture state machine is:

```text
idle --start--> starting
starting --engine ready--> recording
starting --failure--> idle
recording --stop--> stopping --teardown--> idle
recording --iOS interruption begins--> interrupted
interrupted --stop--> stopping
interrupted --resume succeeds--> recording
interrupted --resume declined or fails--> idle
```

`start` is valid only from `idle`; setup failure emits `.failed`, tears down,
returns to `idle`, and throws. `stop` transitions `recording` or `interrupted`
through `stopping` to `idle`; it is a no-op in other states. On iOS, an
interruption pauses capture and resumes only when the system says it should.
Route/configuration changes emit `.routeChanged`; the host decides how to
respond.

## Recording-to-transcription data flow

```text
microphone
  → AVAudioEngine input
  → 16-bit / 16 kHz / mono AudioFrame values
  → UUID.partial in Caches
  → synchronized header + same-directory rename to UUID.wav
  → host-provided SpeechTranscribing implementation
  → host durably persists TranscriptionResult
  → host explicitly deletes the temporary WAV
```

The writer state machine is `writing → finalized` or `writing → discarded`.
Only `writing` accepts matching-format frames. `finalize()` rewrites the WAV
header, synchronizes and closes the file, then renames it from `.partial` to
`.wav`. An append/finalization file error discards the partial file. A finalized
file remains until the host removes it.

Example orchestration (the persistence and transcriber are host-owned):

```swift
import AudioNexusCapture
import AudioNexusTranscription

let store = try TemporaryRecordingStore()
let writer = try await store.makeWriter()

// For each .frame received from MicrophoneCaptureService:
try await writer.append(frame)

let recording = try await writer.finalize()
let request = TranscriptionRequest(audioFileURL: recording.url)
let result = try await transcriber.transcribe(request) // Host implementation.

try await transcriptRepository.save(result)           // Must be durable.
try await store.remove(recording)                      // Delete only afterward.
```

If transcription or persistence fails, keep the WAV for retry or apply an
explicit host retention policy. On launch, remove abandoned `.partial` and
`.wav` files older than a chosen cutoff:

```swift
try await store.cleanupRecordings(
    olderThan: Date(timeIntervalSinceNow: -86_400)
)
```

## Transcription models and security

`TranscriptionModelStore` keeps installed models in
`Application Support/AudioNexus/Models` by default. A
`TranscriptionModelDescriptor` requires a flat filename and a 64-digit SHA-256
value; directory traversal and malformed checksums are rejected.

Installation copies into a random `.partial` file, optionally checks the exact
byte count, always computes SHA-256 in streaming chunks, and publishes the
destination filename only after validation. An already-installed model is
revalidated by default; a size/checksum mismatch removes the invalid installed
copy. Downloads require HTTPS both initially and after redirects and require a
successful HTTP status before installation. Removal is explicit.

The checksum must come from a trusted, pinned source: SHA-256 detects corruption
or substitution relative to that value, but it is not a signature or a model
provenance system. AudioNexus does not bundle a model, choose a model, implement
custom TLS policy, or automatically download anything. Network access occurs
only when the host calls `downloadAndInstall`.

## Privacy and offline assumptions

- Microphone frames and recordings stay on-device unless host code exports
  them. AudioNexus contains no telemetry, analytics, cloud transcription, or
  automatic upload path.
- Capture and file staging require no network. A future local transcriber can
  operate offline after its model is installed, but this repository does not
  yet provide that transcriber.
- Temporary recordings are ordinary files in the app's cache container, and
  models are ordinary files in Application Support. The package adds no
  application-level encryption or secure-delete guarantee.
- The host owns transcript persistence, retention, backup policy, UI
  disclosure, and the decision to delete recordings after durable save.

## Host-app permissions and capabilities

Every host must add a user-facing `NSMicrophoneUsageDescription` to its
`Info.plist`.

- **Sandboxed macOS:** enable App Sandbox **Audio Input**
  (`com.apple.security.device.audio-input`). If the host downloads models,
  enable outgoing network connections
  (`com.apple.security.network.client`).
- **iOS:** microphone access is prompted from the usage description. No extra
  entitlement is needed for foreground recording. AudioNexus does not configure
  background recording; a host that needs it must own and validate that
  lifecycle and capability.

The package writes only inside the host's cache/Application Support containers
by default, so no broad file entitlement is required.

## Repository layout

```text
Package.swift
Sources/
  AudioNexusCore/             PCM format and frame values
  AudioNexusCapture/          capture, conversion, WAV writer/store
  AudioNexusTranscription/    contracts, descriptors, checksum/model store
Tests/
  AudioNexusCoreTests/
  AudioNexusCaptureTests/
  AudioNexusTranscriptionTests/
ROADMAP.md                    milestone status and deferred work
```

## Verification

The test suite covers:

- canonical PCM metadata and frame duration;
- capture defaults and deterministic stereo 48 kHz float to mono 16 kHz
  signed-PCM conversion;
- WAV header/finalization, duration, explicit removal, and stale-file cleanup;
- supported language selection, model filename validation, a standard SHA-256
  vector, verified install/find/remove, and checksum rejection.

This handoff was prepared in a Linux x86_64 environment with no Swift toolchain,
Xcode, or Apple audio frameworks available. Consequently, the Swift suite was
not run here. Run it in the current stable Xcode on supported macOS, then test
from signed host apps on Apple Silicon Mac and physical iPhone hardware.
Package tests alone cannot validate permission prompts, microphones, audio
routes, or interruptions.

## Scope status and next steps

Implemented now: PCM types, microphone capture and conversion, bounded event
delivery, capture/interruption lifecycle, temporary WAV finalization/cleanup,
transcription contracts, language types, and checksum-verified model file
management.

Deferred: Whisper inference/model selection, measured multilingual detection,
RNNoise, ScreenCaptureKit application/system audio, text-to-speech, and physical
device validation. `ROADMAP.md` is the source of truth for milestone status.

Concrete next steps:

1. Build and run all tests with the current stable Xcode.
2. Exercise repeated start/stop, denied permission, interruptions, route
   changes, and cleanup in signed macOS and iOS host apps on physical hardware.
3. Benchmark candidate local Whisper engines/models on supported Apple Silicon
   for memory, latency, accuracy, and English/Spanish/Italian detection.
4. Implement the selected engine behind `SpeechTranscribing`, then add
   fixture-based inference tests without coupling it to capture.

## Companion application boundaries

**BriefScribe** may consume capture, recording, and transcription APIs, but it
owns meeting UX, durable transcript/notes storage, retention policy, templates,
prompting, and any local/cloud provider fallback.

**MythosVox** owns speech-synthesis requirements, voices, presets, and fantasy
pronunciation rules. Those concerns do not belong in AudioNexus until the app
establishes a reusable API requirement.
