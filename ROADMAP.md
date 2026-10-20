# AudioNexus Roadmap

This roadmap records outcomes rather than speculative implementation details.
Work advances only when a consumer application needs the capability.

## 0.1 — Capture foundation

- [x] Create separate core and capture library products.
- [x] Define capture configuration, state, events, and errors.
- [x] Capture microphone buffers with `AVAudioEngine`.
- [x] Convert input to signed 16-bit, 16 kHz mono PCM.
- [x] Add deterministic format and conversion tests.
- [ ] Verify compilation and tests with the current stable Xcode.
- [ ] Verify repeated start and stop on an Apple Silicon Mac and iPhone.

Completion means BriefScribe can consume ordered PCM frames during a meeting
without owning an audio engine or converter.

## 0.2 — Recording lifecycle

- [x] Write frames to a temporary WAV file.
- [x] Finalize files atomically.
- [x] Expose explicit deletion after a transcript is safely persisted.
- [x] Recover and clean stale temporary files after interrupted sessions.
- [x] Handle audio-session interruptions and route changes.
- [ ] Verify interruption recovery and route changes on physical devices.

Completion means BriefScribe can safely implement
record → transcribe → persist transcript → delete recording.

## 0.3 — Local transcription

- [ ] Benchmark practical Whisper model sizes on supported devices.
- [x] Add model identity, checksum, download, and deletion management.
- [x] Keep model files out of Git and out of the package binary.
- [x] Expose transcription independently from capture.
- [ ] Add the selected local Whisper engine behind `SpeechTranscribing`.
- [ ] Verify English, Spanish, and Italian language detection.

Completion means English, Spanish, and Italian meetings can be transcribed
offline with measured memory usage and latency.

## Later, consumer-driven capabilities

- macOS application/system audio through ScreenCaptureKit.
- Optional RNNoise integration after an audible-quality benchmark.
- Speech synthesis only after MythosVox establishes concrete requirements.

Local LLM prompting, note templates, provider fallback policy, voice presets,
and fantasy pronunciation rules belong to their respective applications.
