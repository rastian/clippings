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
            var directory = path.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            try? data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            trimCache(in: path.deletingLastPathComponent())
        }
        return metadata
    }
    private func trimCache(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        let entries = files.compactMap { file -> (URL, Date, Int)? in
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (file, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }.sorted { $0.1 > $1.1 }
        var bytes = 0
        for (file, date, size) in entries {
            if Date().timeIntervalSince(date) > 7 * 24 * 3600 || bytes + size > 50_000_000 { try? FileManager.default.removeItem(at: file) }
            else { bytes += size }
        }
    }

}
