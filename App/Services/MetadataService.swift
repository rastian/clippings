import Foundation
import LinkPresentation
import CryptoKit

@MainActor
protocol MetadataProviding {
    func metadata(for url: URL) async throws -> LPLinkMetadata
}

@MainActor
final class MetadataService: MetadataProviding {
    static let shared = MetadataService()
    private func file(_ url: URL) -> URL {
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return Configuration.directory.appendingPathComponent("Previews", isDirectory: true).appendingPathComponent(key)
    }
    func cached(for url: URL) -> LPLinkMetadata? {
        let path = file(url)
        guard let modified = try? path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              Date().timeIntervalSince(modified) < 7 * 24 * 3600,
              let data = try? Data(contentsOf: path), data.count <= 8_000_000 else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data)
    }
    func metadata(for url: URL) async throws -> LPLinkMetadata {
        if let cached = cached(for: url) { return cached }
        let provider = LPMetadataProvider(); provider.timeout = 8
        let metadata = try await provider.startFetchingMetadata(for: url)
        let path = file(url)
        // A preview failure (including a full cache) must never affect the saved URL.
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: metadata, requiringSecureCoding: true), data.count <= 8_000_000 {
            try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return metadata
    }
}
