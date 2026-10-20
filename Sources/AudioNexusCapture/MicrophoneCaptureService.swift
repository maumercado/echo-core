import AudioNexusCore
import AVFoundation
import Foundation

public actor MicrophoneCaptureService: AudioCapturing {
    public private(set) var state: AudioCaptureState = .idle

    private let eventStream: AsyncStream<AudioCaptureEvent>
    private let eventContinuation: AsyncStream<AudioCaptureEvent>.Continuation
    private var audioEngine: AVAudioEngine?
    private var hasInstalledTap = false

    public init() {
        let stream = AsyncStream.makeStream(
            of: AudioCaptureEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        eventStream = stream.stream
        eventContinuation = stream.continuation
    }

    public func events() -> AsyncStream<AudioCaptureEvent> {
        eventStream
    }

    public func start(
        configuration: AudioCaptureConfiguration = .transcription
    ) async throws {
        guard state == .idle else {
            throw AudioCaptureError.invalidState(
                expected: .idle,
                actual: state
            )
        }

        transition(to: .starting)

        do {
            guard await requestMicrophonePermission() else {
                throw AudioCaptureError.permissionDenied
            }

            try configurePlatformAudioSession()
            try startEngine(configuration: configuration)
            transition(to: .recording)
        } catch {
            tearDownEngine()
            deactivatePlatformAudioSession()
            transition(to: .idle)

            let captureError = mapToCaptureError(error)
            eventContinuation.yield(.failed(captureError))
            throw captureError
        }
    }

    public func stop() async {
        guard state == .recording else {
            return
        }

        transition(to: .stopping)
        tearDownEngine()
        deactivatePlatformAudioSession()
        transition(to: .idle)
    }

    private func startEngine(
        configuration: AudioCaptureConfiguration
    ) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard
            inputFormat.channelCount > 0,
            inputFormat.sampleRate > 0
        else {
            throw AudioCaptureError.unavailableInput
        }

        audioEngine = engine
        let processor = try AudioBufferProcessor(
            inputFormat: inputFormat,
            outputFormat: configuration.outputFormat
        )
        let continuation = eventContinuation
        let bufferSize = Self.bufferSize(
            duration: configuration.bufferDuration,
            sampleRate: inputFormat.sampleRate
        )

        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { buffer, _ in
            do {
                continuation.yield(.frame(try processor.process(buffer)))
            } catch let error as AudioCaptureError {
                continuation.yield(.failed(error))
            } catch {
                continuation.yield(
                    .failed(.conversionFailed(error.localizedDescription))
                )
            }
        }
        hasInstalledTap = true

        engine.prepare()

        do {
            try engine.start()
        } catch {
            throw AudioCaptureError.engineStartFailed(
                error.localizedDescription
            )
        }

    }

    private func tearDownEngine() {
        guard let audioEngine else {
            return
        }

        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        audioEngine.stop()
        self.audioEngine = nil
    }

    private func transition(to newState: AudioCaptureState) {
        state = newState
        eventContinuation.yield(.stateChanged(newState))
    }

    private func requestMicrophonePermission() async -> Bool {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
        #elseif os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
        #endif
    }

    private func configurePlatformAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.allowBluetoothHFP]
        )
        try session.setActive(true)
        #endif
    }

    private func deactivatePlatformAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: [.notifyOthersOnDeactivation]
        )
        #endif
    }

    private func mapToCaptureError(_ error: Error) -> AudioCaptureError {
        if let captureError = error as? AudioCaptureError {
            return captureError
        }

        return .engineStartFailed(error.localizedDescription)
    }

    private static func bufferSize(
        duration: Duration,
        sampleRate: Double
    ) -> AVAudioFrameCount {
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        let requestedFrames = ceil(seconds * sampleRate)
        let clampedFrames = min(
            max(requestedFrames, 1),
            Double(AVAudioFrameCount.max)
        )

        return AVAudioFrameCount(clampedFrames)
    }
}
