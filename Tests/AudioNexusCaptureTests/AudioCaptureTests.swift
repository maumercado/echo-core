@testable import AudioNexusCapture
import AudioNexusCore
import AVFAudio
import Testing

@Test
func transcriptionConfigurationUsesCanonicalDefaults() {
    let configuration = AudioCaptureConfiguration.transcription

    #expect(configuration.source == .microphone)
    #expect(configuration.outputFormat == .transcription)
    #expect(configuration.bufferDuration == .milliseconds(100))
}

@Test
func processorDownsamplesStereoFloatAudioTo16kHzMonoPCM() throws {
    let inputFormat = try #require(
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )
    )
    let inputBuffer = try #require(
        AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: 4_800
        )
    )
    inputBuffer.frameLength = 4_800

    let channels = try #require(inputBuffer.floatChannelData)
    for channelIndex in 0..<Int(inputFormat.channelCount) {
        for frameIndex in 0..<Int(inputBuffer.frameLength) {
            channels[channelIndex][frameIndex] = 0.25
        }
    }

    let processor = try AudioBufferProcessor(
        inputFormat: inputFormat,
        outputFormat: .transcription
    )
    let output = try processor.process(inputBuffer)

    #expect(output.sequenceNumber == 0)
    #expect(output.format == .transcription)
    #expect(output.frameCount > 0)
    #expect(output.frameCount <= 1_600)
    #expect(output.pcmData.count == output.frameCount * 2)
}
