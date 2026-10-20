import AudioNexusCore
import Foundation

public actor TemporaryRecordingStore {
    public let directoryURL: URL

    public init(directoryURL: URL? = nil) throws {
        let resolvedDirectory: URL

        if let directoryURL {
            resolvedDirectory = directoryURL
        } else {
            guard let cacheDirectory = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first else {
                throw AudioRecordingError.storageUnavailable(
                    "The user cache directory is unavailable."
                )
            }

            resolvedDirectory = cacheDirectory
                .appendingPathComponent("AudioNexus", isDirectory: true)
                .appendingPathComponent("Recordings", isDirectory: true)
        }

        do {
            try FileManager.default.createDirectory(
                at: resolvedDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw AudioRecordingError.storageUnavailable(
                error.localizedDescription
            )
        }

        self.directoryURL = resolvedDirectory.standardizedFileURL
    }

    public func makeWriter(
        format: AudioPCMFormat = .transcription
    ) throws -> WAVRecordingWriter {
        try WAVRecordingWriter(
            directoryURL: directoryURL,
            format: format
        )
    }

    /// Deletes a finalized recording after its durable consumer has succeeded.
    public func remove(_ recording: RecordedAudioFile) throws {
        guard contains(recording.url) else {
            throw AudioRecordingError.recordingOutsideStore
        }

        do {
            try FileManager.default.removeItem(at: recording.url)
        } catch {
            throw AudioRecordingError.fileOperationFailed(
                error.localizedDescription
            )
        }
    }

    /// Removes abandoned partial and finalized recordings older than `cutoff`.
    @discardableResult
    public func cleanupRecordings(olderThan cutoff: Date) throws -> Int {
        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isRegularFileKey,
        ]

        do {
            let candidates = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )

            return try candidates.reduce(into: 0) { removalCount, url in
                guard Self.isRecordingFile(url) else {
                    return
                }

                let values = try url.resourceValues(forKeys: resourceKeys)
                guard
                    values.isRegularFile == true,
                    let modificationDate = values.contentModificationDate,
                    modificationDate < cutoff
                else {
                    return
                }

                try FileManager.default.removeItem(at: url)
                removalCount += 1
            }
        } catch let error as AudioRecordingError {
            throw error
        } catch {
            throw AudioRecordingError.fileOperationFailed(
                error.localizedDescription
            )
        }
    }

    private func contains(_ url: URL) -> Bool {
        url.standardizedFileURL
            .deletingLastPathComponent() == directoryURL
    }

    private static func isRecordingFile(_ url: URL) -> Bool {
        url.pathExtension == "partial" || url.pathExtension == "wav"
    }
}
