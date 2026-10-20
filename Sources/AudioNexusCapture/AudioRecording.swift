import AudioNexusCore
import Foundation

public struct RecordedAudioFile: Equatable, Sendable {
    public let url: URL
    public let format: AudioPCMFormat
    public let frameCount: UInt64

    init(
        url: URL,
        format: AudioPCMFormat,
        frameCount: UInt64
    ) {
        self.url = url
        self.format = format
        self.frameCount = frameCount
    }

    public var duration: Duration {
        .seconds(Double(frameCount) / Double(format.sampleRate))
    }
}

public enum AudioRecordingWriterState: Equatable, Sendable {
    case writing
    case finalized
    case discarded
}

public enum AudioRecordingError: Error, Equatable, Sendable {
    case storageUnavailable(String)
    case invalidState(
        expected: AudioRecordingWriterState,
        actual: AudioRecordingWriterState
    )
    case mismatchedFormat
    case unsupportedFormat
    case fileTooLarge
    case recordingOutsideStore
    case fileOperationFailed(String)
}
