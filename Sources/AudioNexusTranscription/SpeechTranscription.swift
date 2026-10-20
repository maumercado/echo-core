import Foundation

public enum TranscriptionLanguage: String, CaseIterable, Hashable, Sendable {
    case english = "en"
    case spanish = "es"
    case italian = "it"
}

public enum TranscriptionLanguageSelection: Equatable, Sendable {
    case automatic(allowed: Set<TranscriptionLanguage>)
    case fixed(TranscriptionLanguage)

    public static let automaticSupported = TranscriptionLanguageSelection
        .automatic(allowed: Set(TranscriptionLanguage.allCases))
}

public struct TranscriptionRequest: Equatable, Sendable {
    public let audioFileURL: URL
    public let languageSelection: TranscriptionLanguageSelection
    public let includesSegments: Bool

    public init(
        audioFileURL: URL,
        languageSelection: TranscriptionLanguageSelection = .automaticSupported,
        includesSegments: Bool = true
    ) {
        self.audioFileURL = audioFileURL
        self.languageSelection = languageSelection
        self.includesSegments = includesSegments
    }
}

public struct TranscriptionSegment: Equatable, Sendable {
    public let text: String
    public let startTime: Duration
    public let endTime: Duration

    public init(
        text: String,
        startTime: Duration,
        endTime: Duration
    ) {
        precondition(startTime >= .zero, "Start time cannot be negative.")
        precondition(endTime >= startTime, "End time cannot precede start time.")

        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct TranscriptionResult: Equatable, Sendable {
    public let text: String
    public let detectedLanguage: TranscriptionLanguage
    public let segments: [TranscriptionSegment]

    public init(
        text: String,
        detectedLanguage: TranscriptionLanguage,
        segments: [TranscriptionSegment]
    ) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.segments = segments
    }
}

public enum TranscriptionError: Error, Equatable, Sendable {
    case audioFileNotFound
    case invalidLanguageSelection
    case unsupportedAudio
    case modelUnavailable(String)
    case languageDetectionFailed
    case engineFailure(String)
}

public protocol SpeechTranscribing: Sendable {
    func transcribe(
        _ request: TranscriptionRequest
    ) async throws -> TranscriptionResult
}
