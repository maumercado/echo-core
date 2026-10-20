import AudioNexusCore
import AVFAudio
import Foundation

/// Owns the non-Sendable AVAudioConverter used by the real-time tap.
///
/// AVAudioEngine invokes a tap serially. The unchecked conformance documents
/// that this processor must remain owned by exactly one installed tap.
final class AudioBufferProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outputAVFormat: AVAudioFormat
    private let outputFormat: AudioPCMFormat
    private var sequenceNumber: UInt64 = 0

    init(
        inputFormat: AVAudioFormat,
        outputFormat: AudioPCMFormat
    ) throws {
        guard
            outputFormat.bitsPerChannel == 16,
            let outputAVFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(outputFormat.sampleRate),
                channels: AVAudioChannelCount(outputFormat.channelCount),
                interleaved: true
            )
        else {
            throw AudioCaptureError.unsupportedOutputFormat
        }

        guard let converter = AVAudioConverter(
            from: inputFormat,
            to: outputAVFormat
        ) else {
            throw AudioCaptureError.converterCreationFailed
        }

        self.converter = converter
        self.outputAVFormat = outputAVFormat
        self.outputFormat = outputFormat
    }

    func process(_ inputBuffer: AVAudioPCMBuffer) throws -> AudioFrame {
        let rateRatio = outputAVFormat.sampleRate / inputBuffer.format.sampleRate
        let estimatedFrameCount = ceil(Double(inputBuffer.frameLength) * rateRatio)
        let outputCapacity = AVAudioFrameCount(max(estimatedFrameCount, 1))

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputAVFormat,
            frameCapacity: outputCapacity
        ) else {
            throw AudioCaptureError.conversionFailed(
                "Could not allocate the output buffer."
            )
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }

            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error else {
            throw AudioCaptureError.conversionFailed(
                conversionError?.localizedDescription ?? "Unknown conversion error."
            )
        }

        guard let samples = outputBuffer.int16ChannelData?[0] else {
            throw AudioCaptureError.conversionFailed(
                "The converter produced an unexpected sample layout."
            )
        }

        let frameCount = Int(outputBuffer.frameLength)
        let pcmData = Data(
            bytes: samples,
            count: frameCount * outputFormat.bytesPerFrame
        )
        defer { sequenceNumber += 1 }

        return AudioFrame(
            sequenceNumber: sequenceNumber,
            frameCount: frameCount,
            format: outputFormat,
            pcmData: pcmData
        )
    }
}
