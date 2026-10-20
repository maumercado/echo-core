# AudioNexus

AudioNexus is a private Swift package for reusable, on-device audio capture and
processing on current Apple platforms. The first release focuses on reliable
microphone capture and emits little-endian, signed 16-bit, 16 kHz mono PCM
frames suitable for speech transcription.

## Requirements

- Apple Silicon Mac
- Current stable Xcode
- macOS 27 or later
- iOS 27 or later
- Swift 6 language mode

The host application must provide `NSMicrophoneUsageDescription`. A sandboxed
macOS application must also enable the Audio Input capability.

## Products

- `AudioNexusCore`: platform-neutral PCM value types.
- `AudioNexusCapture`: microphone capture and format conversion.

Native transcription, denoising, and speech synthesis will remain separate
products so applications only link the capabilities they use.

## Usage

```swift
import AudioNexusCapture

let captureService = MicrophoneCaptureService()
let events = await captureService.events()

let eventTask = Task {
    for await event in events {
        switch event {
        case let .frame(frame):
            // Consume frame.pcmData without blocking the capture callback.
            print("Received \(frame.frameCount) frames")
        case let .failed(error):
            print("Capture failed: \(error)")
        default:
            break
        }
    }
}

try await captureService.start()

// Later:
await captureService.stop()
eventTask.cancel()
```

The event stream retains at most 64 pending events. Consumers should process
or hand off frames promptly so stale audio is not dropped.

## Temporary WAV lifecycle

`TemporaryRecordingStore` creates writers in an application cache directory.
Finalization rewrites the WAV header, closes and synchronizes the file, then
renames it from `.partial` to `.wav` on the same filesystem.

```swift
let store = try TemporaryRecordingStore()
let writer = try await store.makeWriter()

// Append each frame received from MicrophoneCaptureService.
try await writer.append(frame)

let recording = try await writer.finalize()

// Transcribe recording.url and durably save the transcript first.
try await store.remove(recording)
```

The package does not guess whether transcription succeeded. The application
must call `remove(_:)` only after its transcript is durable. On launch, the
application can remove crash remnants with:

```swift
try await store.cleanupRecordings(
    olderThan: Date(timeIntervalSinceNow: -86_400)
)
```

## Development

Open the package in the current stable Xcode and run the package test suite.
Hardware microphone behavior must also be checked from a signed host
application because package tests cannot exercise permission prompts or real
audio-route changes reliably.

The package intentionally has no third-party dependencies in its capture
foundation.
