@testable import AudioNexusTranscription
import Foundation
import Testing

@Test
func automaticLanguageSelectionIncludesSupportedMeetingLanguages() {
    let selection = TranscriptionLanguageSelection.automaticSupported

    #expect(
        selection == .automatic(
            allowed: [.english, .spanish, .italian]
        )
    )
}

@Test
func modelDescriptorRejectsDirectoryTraversal() {
    do {
        _ = try TranscriptionModelDescriptor(
            identifier: "unsafe",
            fileName: "../model.bin",
            sha256: String(repeating: "0", count: 64)
        )
        Issue.record("A model filename must not escape the model store.")
    } catch let error as TranscriptionModelError {
        guard case .invalidDescriptor = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func checksumUsesTheStandardSHA256Representation() throws {
    let directoryURL = try makeModelTestDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let fileURL = directoryURL.appendingPathComponent("known-vector")
    try Data("abc".utf8).write(to: fileURL)

    #expect(
        try ModelFileChecksum.sha256(of: fileURL)
            == "ba7816bf8f01cfea414140de5dae2223"
            + "b00361a396177a9cb410ff61f20015ad"
    )
}

@Test
func modelStoreVerifiesInstallsFindsAndRemovesAModel() async throws {
    let rootURL = try makeModelTestDirectory()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let sourceURL = rootURL.appendingPathComponent("source.bin")
    let modelDirectoryURL = rootURL.appendingPathComponent(
        "installed",
        isDirectory: true
    )
    let modelData = Data("verified-model".utf8)
    try modelData.write(to: sourceURL)

    let descriptor = try TranscriptionModelDescriptor(
        identifier: "test-model",
        fileName: "test-model.bin",
        sha256: ModelFileChecksum.sha256(of: sourceURL),
        expectedByteCount: Int64(modelData.count)
    )
    let store = try TranscriptionModelStore(
        directoryURL: modelDirectoryURL
    )

    let installedURL = try await store.installModel(
        from: sourceURL,
        descriptor: descriptor
    )

    #expect(FileManager.default.fileExists(atPath: installedURL.path))
    #expect(
        try await store.installedModelURL(for: descriptor) == installedURL
    )

    try await store.removeModel(descriptor)
    #expect(!FileManager.default.fileExists(atPath: installedURL.path))
    #expect(FileManager.default.fileExists(atPath: sourceURL.path))
}

@Test
func modelStoreRejectsAnInvalidChecksum() async throws {
    let rootURL = try makeModelTestDirectory()
    defer { try? FileManager.default.removeItem(at: rootURL) }

    let sourceURL = rootURL.appendingPathComponent("source.bin")
    try Data("tampered".utf8).write(to: sourceURL)

    let descriptor = try TranscriptionModelDescriptor(
        identifier: "test-model",
        fileName: "test-model.bin",
        sha256: String(repeating: "0", count: 64)
    )
    let store = try TranscriptionModelStore(
        directoryURL: rootURL.appendingPathComponent("installed")
    )

    do {
        _ = try await store.installModel(
            from: sourceURL,
            descriptor: descriptor
        )
        Issue.record("Installation should reject a mismatched checksum.")
    } catch let error as TranscriptionModelError {
        guard case let .checksumMismatch(expected, actual) = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }

        #expect(expected == descriptor.sha256)
        #expect(actual != descriptor.sha256)
    }
}

private func makeModelTestDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: true
    )
    return url
}
