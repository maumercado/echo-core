import AudioNexusCore
import Foundation

public enum AudioCaptureSource: Equatable, Sendable {
    case microphone
}

public struct AudioCaptureConfiguration: Equatable, Sendable {
    public let source: AudioCaptureSource
    public let outputFormat: AudioPCMFormat
    public let bufferDuration: Duration

    public init(
        source: AudioCaptureSource = .microphone,
        outputFormat: AudioPCMFormat = .transcription,
        bufferDuration: Duration = .milliseconds(100)
    ) {
        precondition(bufferDuration > .zero, "Buffer duration must be positive.")

        self.source = source
        self.outputFormat = outputFormat
        self.bufferDuration = bufferDuration
    }

    public static let transcription = AudioCaptureConfiguration()
}

public enum AudioCaptureState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case interrupted
    case stopping
}

public enum AudioCaptureInterruption: Equatable, Sendable {
    case began
    case ended(shouldResume: Bool)
}

public enum AudioCaptureEvent: Equatable, Sendable {
    case stateChanged(AudioCaptureState)
    case frame(AudioFrame)
    case interruption(AudioCaptureInterruption)
    case routeChanged
    case failed(AudioCaptureError)
}

public enum AudioCaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case invalidState(expected: AudioCaptureState, actual: AudioCaptureState)
    case unavailableInput
    case unsupportedOutputFormat
    case converterCreationFailed
    case conversionFailed(String)
    case engineStartFailed(String)
}

public protocol AudioCapturing: Actor {
    var state: AudioCaptureState { get }

    func events() -> AsyncStream<AudioCaptureEvent>
    func start(configuration: AudioCaptureConfiguration) async throws
    func stop() async
}
