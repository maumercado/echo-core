import AudioNexusCore
import AVFoundation
import Foundation

public actor MicrophoneCaptureService: AudioCapturing {
    public private(set) var state: AudioCaptureState = .idle

    private let eventStream: AsyncStream<AudioCaptureEvent>
    private let eventContinuation: AsyncStream<AudioCaptureEvent>.Continuation
    private var audioEngine: AVAudioEngine?
    private var hasInstalledTap = false
    private var observerTokens: [NSObjectProtocol] = []

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
        guard state == .recording || state == .interrupted else {
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

        installObservers(for: engine)
    }

    private func tearDownEngine() {
        removeObservers()

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

    private func installObservers(for engine: AVAudioEngine) {
        let notificationCenter = NotificationCenter.default
        let continuation = eventContinuation

        observerTokens.append(
            notificationCenter.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: nil
            ) { _ in
                continuation.yield(.routeChanged)
            }
        )

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()

        observerTokens.append(
            notificationCenter.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: nil
            ) { _ in
                continuation.yield(.routeChanged)
            }
        )

        observerTokens.append(
            notificationCenter.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: nil
            ) { [weak self] notification in
                guard
                    let rawType = notification.userInfo?[
                        AVAudioSessionInterruptionTypeKey
                    ] as? UInt,
                    let interruptionType = AVAudioSession.InterruptionType(
                        rawValue: rawType
                    )
                else {
                    return
                }

                let interruption: AudioCaptureInterruption

                switch interruptionType {
                case .began:
                    interruption = .began
                case .ended:
                    let rawOptions = notification.userInfo?[
                        AVAudioSessionInterruptionOptionKey
                    ] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(
                        rawValue: rawOptions
                    )
                    interruption = .ended(
                        shouldResume: options.contains(.shouldResume)
                    )
                @unknown default:
                    return
                }

                Task {
                    await self?.handleInterruption(interruption)
                }
            }
        )
        #endif
    }

    private func removeObservers() {
        let notificationCenter = NotificationCenter.default
        observerTokens.forEach {
            notificationCenter.removeObserver($0)
        }
        observerTokens.removeAll()
    }

    private func handleInterruption(
        _ interruption: AudioCaptureInterruption
    ) {
        eventContinuation.yield(.interruption(interruption))

        switch interruption {
        case .began:
            guard state == .recording else {
                return
            }

            audioEngine?.pause()
            transition(to: .interrupted)

        case let .ended(shouldResume):
            guard state == .interrupted else {
                return
            }

            guard shouldResume else {
                tearDownEngine()
                deactivatePlatformAudioSession()
                transition(to: .idle)
                return
            }

            do {
                try configurePlatformAudioSession()
                guard let audioEngine else {
                    throw AudioCaptureError.unavailableInput
                }
                try audioEngine.start()
                transition(to: .recording)
            } catch {
                let captureError = mapToCaptureError(error)
                eventContinuation.yield(.failed(captureError))
                tearDownEngine()
                deactivatePlatformAudioSession()
                transition(to: .idle)
            }
        }
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
