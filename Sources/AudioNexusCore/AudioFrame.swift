import Foundation

/// The canonical PCM format emitted by AudioNexus capture services.
public struct AudioPCMFormat: Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let bitsPerChannel: Int

    public init(
        sampleRate: Int,
        channelCount: Int,
        bitsPerChannel: Int
    ) {
        precondition(sampleRate > 0, "Sample rate must be positive.")
        precondition(channelCount > 0, "Channel count must be positive.")
        precondition(bitsPerChannel > 0, "Bits per channel must be positive.")

        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitsPerChannel = bitsPerChannel
    }

    public static let transcription = AudioPCMFormat(
        sampleRate: 16_000,
        channelCount: 1,
        bitsPerChannel: 16
    )

    public var bytesPerFrame: Int {
        channelCount * bitsPerChannel / 8
    }
}

/// A sequential chunk of little-endian, signed-integer PCM audio.
public struct AudioFrame: Equatable, Sendable {
    public let sequenceNumber: UInt64
    public let frameCount: Int
    public let format: AudioPCMFormat
    public let pcmData: Data

    public init(
        sequenceNumber: UInt64,
        frameCount: Int,
        format: AudioPCMFormat,
        pcmData: Data
    ) {
        precondition(frameCount >= 0, "Frame count cannot be negative.")
        precondition(
            pcmData.count == frameCount * format.bytesPerFrame,
            "PCM byte count must match the frame count and format."
        )

        self.sequenceNumber = sequenceNumber
        self.frameCount = frameCount
        self.format = format
        self.pcmData = pcmData
    }

    public var duration: Duration {
        .seconds(Double(frameCount) / Double(format.sampleRate))
    }
}
