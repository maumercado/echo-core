import CryptoKit
import Foundation

enum ModelFileChecksum {
    static func sha256(of fileURL: URL) throws -> String {
        do {
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? fileHandle.close() }

            var hasher = SHA256()

            while let data = try fileHandle.read(upToCount: 1_048_576),
                  !data.isEmpty {
                hasher.update(data: data)
            }

            return hasher.finalize()
                .map { String(format: "%02x", $0) }
                .joined()
        } catch {
            throw TranscriptionModelError.fileOperationFailed(
                error.localizedDescription
            )
        }
    }
}
