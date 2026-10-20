import AudioNexusCore
import Foundation

public actor WAVRecordingWriter {
    public private(set) var state: AudioRecordingWriterState = .writing

    private let format: AudioPCMFormat
    private let partialURL: URL
    private let finalizedURL: URL
    private var fileHandle: FileHandle?
    private var frameCount: UInt64 = 0

    init(
        directoryURL: URL,
        format: AudioPCMFormat,
        identifier: UUID = UUID()
    ) throws {
        guard
            format.bitsPerChannel == 16,
            UInt16(exactly: format.channelCount) != nil,
            UInt32(exactly: format.sampleRate) != nil
        else {
            throw AudioRecordingError.unsupportedFormat
        }

        self.format = format
        partialURL = directoryURL
            .appendingPathComponent(identifier.uuidString)
            .appendingPathExtension("partial")
        finalizedURL = directoryURL
            .appendingPathComponent(identifier.uuidString)
            .appendingPathExtension("wav")

        do {
            let emptyHeader = try Self.makeHeader(
                format: format,
                dataByteCount: 0
            )
            guard FileManager.default.createFile(
                atPath: partialURL.path,
                contents: emptyHeader
            ) else {
                throw AudioRecordingError.fileOperationFailed(
                    "Could not create a temporary recording."
                )
            }

            let handle = try FileHandle(forWritingTo: partialURL)
            try handle.seekToEnd()
            fileHandle = handle
        } catch let error as AudioRecordingError {
            throw error
        } catch {
            throw AudioRecordingError.fileOperationFailed(
                error.localizedDescription
            )
        }
    }

    public func append(_ frame: AudioFrame) throws {
        guard state == .writing else {
            throw AudioRecordingError.invalidState(
                expected: .writing,
                actual: state
            )
        }
        guard frame.format == format else {
            throw AudioRecordingError.mismatchedFormat
        }

        let nextByteCount = (frameCount + UInt64(frame.frameCount))
            * UInt64(format.bytesPerFrame)
        guard nextByteCount <= UInt64(UInt32.max - 36) else {
            throw AudioRecordingError.fileTooLarge
        }

        do {
            try fileHandle?.write(contentsOf: frame.pcmData)
            frameCount += UInt64(frame.frameCount)
        } catch {
            discardFile()
            throw AudioRecordingError.fileOperationFailed(
                error.localizedDescription
            )
        }
    }

    public func finalize() throws -> RecordedAudioFile {
        guard state == .writing else {
            throw AudioRecordingError.invalidState(
                expected: .writing,
                actual: state
            )
        }

        do {
            let dataByteCount = frameCount * UInt64(format.bytesPerFrame)
            let header = try Self.makeHeader(
                format: format,
                dataByteCount: dataByteCount
            )

            try fileHandle?.seek(toOffset: 0)
            try fileHandle?.write(contentsOf: header)
            try fileHandle?.synchronize()
            try fileHandle?.close()
            fileHandle = nil

            try FileManager.default.moveItem(
                at: partialURL,
                to: finalizedURL
            )
            state = .finalized

            return RecordedAudioFile(
                url: finalizedURL,
                format: format,
                frameCount: frameCount
            )
        } catch let error as AudioRecordingError {
            discardFile()
            throw error
        } catch {
            discardFile()
            throw AudioRecordingError.fileOperationFailed(
                error.localizedDescription
            )
        }
    }

    public func discard() throws {
        guard state == .writing else {
            throw AudioRecordingError.invalidState(
                expected: .writing,
                actual: state
            )
        }

        discardFile()
    }

    private func discardFile() {
        try? fileHandle?.close()
        fileHandle = nil
        try? FileManager.default.removeItem(at: partialURL)
        state = .discarded
    }

    private static func makeHeader(
        format: AudioPCMFormat,
        dataByteCount: UInt64
    ) throws -> Data {
        guard
            dataByteCount <= UInt64(UInt32.max - 36),
            let dataSize = UInt32(exactly: dataByteCount),
            let sampleRate = UInt32(exactly: format.sampleRate),
            let channelCount = UInt16(exactly: format.channelCount),
            let bitsPerChannel = UInt16(exactly: format.bitsPerChannel),
            let blockAlignment = UInt16(
                exactly: format.channelCount * format.bitsPerChannel / 8
            ),
            let byteRate = UInt32(
                exactly: format.sampleRate * format.bytesPerFrame
            )
        else {
            throw AudioRecordingError.fileTooLarge
        }

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.appendInteger(UInt32(36) + dataSize)
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.appendInteger(UInt32(16))
        header.appendInteger(UInt16(1))
        header.appendInteger(channelCount)
        header.appendInteger(sampleRate)
        header.appendInteger(byteRate)
        header.appendInteger(blockAlignment)
        header.appendInteger(bitsPerChannel)
        header.append(contentsOf: "data".utf8)
        header.appendInteger(dataSize)

        return header
    }
}

private extension Data {
    mutating func appendInteger<Integer: FixedWidthInteger>(_ value: Integer) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }
}
