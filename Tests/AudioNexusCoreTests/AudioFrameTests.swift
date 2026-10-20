import AudioNexusCore
import Foundation
import Testing

@Test
func transcriptionFormatDescribes16BitMonoPCM() {
    let format = AudioPCMFormat.transcription

    #expect(format.sampleRate == 16_000)
    #expect(format.channelCount == 1)
    #expect(format.bitsPerChannel == 16)
    #expect(format.bytesPerFrame == 2)
}

@Test
func audioFrameReportsItsDuration() {
    let frameCount = 1_600
    let frame = AudioFrame(
        sequenceNumber: 7,
        frameCount: frameCount,
        format: .transcription,
        pcmData: Data(count: frameCount * AudioPCMFormat.transcription.bytesPerFrame)
    )

    #expect(frame.sequenceNumber == 7)
    #expect(frame.duration == .milliseconds(100))
}
