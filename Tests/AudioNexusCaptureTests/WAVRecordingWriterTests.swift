@testable import AudioNexusCapture
import AudioNexusCore
import Foundation
import Testing

@Test
func writerFinalizesAValidPCMFileAndStoreRemovesIt() async throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let store = try TemporaryRecordingStore(directoryURL: directoryURL)
    let writer = try await store.makeWriter()
    let frame = makeFrame(sequenceNumber: 0, frameCount: 1_600)

    try await writer.append(frame)
    let recording = try await writer.finalize()
    let fileData = try Data(contentsOf: recording.url)

    #expect(fileData.count == 44 + frame.pcmData.count)
    #expect(String(decoding: fileData[0..<4], as: UTF8.self) == "RIFF")
    #expect(String(decoding: fileData[8..<12], as: UTF8.self) == "WAVE")
    #expect(readUInt16(fileData, offset: 22) == 1)
    #expect(readUInt32(fileData, offset: 24) == 16_000)
    #expect(readUInt16(fileData, offset: 34) == 16)
    #expect(readUInt32(fileData, offset: 40) == UInt32(frame.pcmData.count))
    #expect(recording.duration == .milliseconds(100))

    try await store.remove(recording)
    #expect(!FileManager.default.fileExists(atPath: recording.url.path))
}

@Test
func cleanupRemovesOnlyStaleAudioNexusRecordings() async throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let store = try TemporaryRecordingStore(directoryURL: directoryURL)
    let writer = try await store.makeWriter()
    try await writer.append(makeFrame(sequenceNumber: 0, frameCount: 160))
    let recording = try await writer.finalize()

    let unrelatedURL = directoryURL.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: unrelatedURL)
    let staleDate = Date(timeIntervalSinceNow: -7_200)
    try FileManager.default.setAttributes(
        [.modificationDate: staleDate],
        ofItemAtPath: recording.url.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: staleDate],
        ofItemAtPath: unrelatedURL.path
    )

    let removalCount = try await store.cleanupRecordings(
        olderThan: Date(timeIntervalSinceNow: -3_600)
    )

    #expect(removalCount == 1)
    #expect(!FileManager.default.fileExists(atPath: recording.url.path))
    #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}

private func makeFrame(
    sequenceNumber: UInt64,
    frameCount: Int
) -> AudioFrame {
    AudioFrame(
        sequenceNumber: sequenceNumber,
        frameCount: frameCount,
        format: .transcription,
        pcmData: Data(
            repeating: 0x01,
            count: frameCount * AudioPCMFormat.transcription.bytesPerFrame
        )
    )
}

private func readUInt16(_ data: Data, offset: Int) -> UInt16 {
    UInt16(data[offset])
        | UInt16(data[offset + 1]) << 8
}

private func readUInt32(_ data: Data, offset: Int) -> UInt32 {
    UInt32(data[offset])
        | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16
        | UInt32(data[offset + 3]) << 24
}
