import Foundation

public struct TranscriptionModelDescriptor: Equatable, Hashable, Sendable {
    public let identifier: String
    public let fileName: String
    public let downloadURL: URL?
    public let sha256: String
    public let expectedByteCount: Int64?

    public init(
        identifier: String,
        fileName: String,
        downloadURL: URL? = nil,
        sha256: String,
        expectedByteCount: Int64? = nil
    ) throws {
        let normalizedChecksum = sha256.lowercased()

        guard !identifier.isEmpty else {
            throw TranscriptionModelError.invalidDescriptor(
                "The model identifier cannot be empty."
            )
        }
        guard
            !fileName.isEmpty,
            fileName != ".",
            fileName != "..",
            !fileName.contains("/"),
            URL(fileURLWithPath: fileName).lastPathComponent == fileName
        else {
            throw TranscriptionModelError.invalidDescriptor(
                "The model filename must not contain a directory."
            )
        }
        guard
            normalizedChecksum.count == 64,
            normalizedChecksum.allSatisfy(\.isHexDigit)
        else {
            throw TranscriptionModelError.invalidDescriptor(
                "The SHA-256 checksum must contain 64 hexadecimal characters."
            )
        }
        if let expectedByteCount, expectedByteCount <= 0 {
            throw TranscriptionModelError.invalidDescriptor(
                "The expected byte count must be positive."
            )
        }

        self.identifier = identifier
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.sha256 = normalizedChecksum
        self.expectedByteCount = expectedByteCount
    }
}

public enum TranscriptionModelError: Error, Equatable, Sendable {
    case invalidDescriptor(String)
    case storageUnavailable(String)
    case modelNotInstalled(String)
    case downloadURLMissing(String)
    case insecureDownloadURL
    case unexpectedHTTPStatus(Int)
    case downloadFailed(String)
    case unexpectedByteCount(expected: Int64, actual: Int64)
    case checksumMismatch(expected: String, actual: String)
    case fileOperationFailed(String)
}
