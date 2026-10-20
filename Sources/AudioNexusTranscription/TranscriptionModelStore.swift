import Foundation

public actor TranscriptionModelStore {
    public let directoryURL: URL

    public init(directoryURL: URL? = nil) throws {
        let resolvedDirectory: URL

        if let directoryURL {
            resolvedDirectory = directoryURL
        } else {
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw TranscriptionModelError.storageUnavailable(
                    "The application support directory is unavailable."
                )
            }

            resolvedDirectory = applicationSupport
                .appendingPathComponent("AudioNexus", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }

        do {
            try FileManager.default.createDirectory(
                at: resolvedDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw TranscriptionModelError.storageUnavailable(
                error.localizedDescription
            )
        }

        self.directoryURL = resolvedDirectory.standardizedFileURL
    }

    public func installedModelURL(
        for descriptor: TranscriptionModelDescriptor,
        verifyIntegrity: Bool = true
    ) throws -> URL? {
        let modelURL = destinationURL(for: descriptor)

        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            return nil
        }

        if verifyIntegrity {
            try validateModel(at: modelURL, descriptor: descriptor)
        }

        return modelURL
    }

    public func installModel(
        from sourceURL: URL,
        descriptor: TranscriptionModelDescriptor
    ) throws -> URL {
        let modelURL = destinationURL(for: descriptor)

        if FileManager.default.fileExists(atPath: modelURL.path) {
            do {
                try validateModel(at: modelURL, descriptor: descriptor)
                return modelURL
            } catch let error as TranscriptionModelError {
                switch error {
                case .checksumMismatch, .unexpectedByteCount:
                    try? FileManager.default.removeItem(at: modelURL)
                default:
                    throw error
                }
            }
        }

        let partialURL = directoryURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("partial")
        defer { try? FileManager.default.removeItem(at: partialURL) }

        do {
            try FileManager.default.copyItem(
                at: sourceURL,
                to: partialURL
            )
            try validateModel(at: partialURL, descriptor: descriptor)

            try FileManager.default.moveItem(
                at: partialURL,
                to: modelURL
            )

            return modelURL
        } catch let error as TranscriptionModelError {
            throw error
        } catch {
            throw TranscriptionModelError.fileOperationFailed(
                error.localizedDescription
            )
        }
    }

    public func downloadAndInstall(
        _ descriptor: TranscriptionModelDescriptor
    ) async throws -> URL {
        guard let downloadURL = descriptor.downloadURL else {
            throw TranscriptionModelError.downloadURLMissing(
                descriptor.identifier
            )
        }
        guard downloadURL.scheme?.lowercased() == "https" else {
            throw TranscriptionModelError.insecureDownloadURL
        }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(
                from: downloadURL
            )

            guard response.url?.scheme?.lowercased() == "https" else {
                throw TranscriptionModelError.insecureDownloadURL
            }
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw TranscriptionModelError.unexpectedHTTPStatus(
                    httpResponse.statusCode
                )
            }

            return try installModel(
                from: temporaryURL,
                descriptor: descriptor
            )
        } catch let error as TranscriptionModelError {
            throw error
        } catch {
            throw TranscriptionModelError.downloadFailed(
                error.localizedDescription
            )
        }
    }

    public func removeModel(
        _ descriptor: TranscriptionModelDescriptor
    ) throws {
        let modelURL = destinationURL(for: descriptor)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriptionModelError.modelNotInstalled(
                descriptor.identifier
            )
        }

        do {
            try FileManager.default.removeItem(at: modelURL)
        } catch {
            throw TranscriptionModelError.fileOperationFailed(
                error.localizedDescription
            )
        }
    }

    private func destinationURL(
        for descriptor: TranscriptionModelDescriptor
    ) -> URL {
        directoryURL.appendingPathComponent(descriptor.fileName)
    }

    private func validateModel(
        at fileURL: URL,
        descriptor: TranscriptionModelDescriptor
    ) throws {
        if let expectedByteCount = descriptor.expectedByteCount {
            let attributes: [FileAttributeKey: Any]

            do {
                attributes = try FileManager.default.attributesOfItem(
                    atPath: fileURL.path
                )
            } catch {
                throw TranscriptionModelError.fileOperationFailed(
                    error.localizedDescription
                )
            }

            let actualByteCount = (
                attributes[.size] as? NSNumber
            )?.int64Value ?? -1

            guard actualByteCount == expectedByteCount else {
                throw TranscriptionModelError.unexpectedByteCount(
                    expected: expectedByteCount,
                    actual: actualByteCount
                )
            }
        }

        let actualChecksum = try ModelFileChecksum.sha256(of: fileURL)
        guard actualChecksum == descriptor.sha256 else {
            throw TranscriptionModelError.checksumMismatch(
                expected: descriptor.sha256,
                actual: actualChecksum
            )
        }
    }
}
