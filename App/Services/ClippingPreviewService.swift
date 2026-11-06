import Foundation
import UIKit
import LinkPresentation

struct ClippingPreview {
    var title: String?
    var image: UIImage?
    var excerpt: String?
}

@MainActor
final class ClippingPreviewService {
    static let shared = ClippingPreviewService()
    private final class Entry {
        let preview: ClippingPreview
        let date = Date()
        init(_ preview: ClippingPreview) { self.preview = preview }
    }
    private let cache = NSCache<NSString, Entry>()
    private var pending: [URL: Task<ClippingPreview, Never>] = [:]
    private let metadataProvider: any MetadataProviding
    private let loadExcerpt: @Sendable (URL) async -> String?
    init(metadataProvider: any MetadataProviding = MetadataService.shared,
         loadExcerpt: @escaping @Sendable (URL) async -> String? = { await ExcerptService.shared.excerpt(for: $0) }) {
        self.metadataProvider = metadataProvider; self.loadExcerpt = loadExcerpt
        cache.countLimit = 60; cache.totalCostLimit = 30_000_000
    }

    func preview(for url: URL) async -> ClippingPreview {
        if let entry = cache.object(forKey: url.absoluteString as NSString), Date().timeIntervalSince(entry.date) < 300 { return entry.preview }
        if let task = pending[url] { return await task.value }
        let task = Task { @MainActor in
            async let excerpt = loadExcerpt(url)
            let metadata = try? await metadataProvider.metadata(for: url)
            var image: UIImage?
            if let provider = metadata?.imageProvider, provider.canLoadObject(ofClass: UIImage.self) {
                image = await withCheckedContinuation { continuation in
                    provider.loadObject(ofClass: UIImage.self) { object, _ in
                        continuation.resume(returning: object as? UIImage)
                    }
                }
                image = image?.preparingThumbnail(of: CGSize(width: 800, height: 600))
            }
            return ClippingPreview(title: metadata?.title, image: image, excerpt: await excerpt)
        }
        pending[url] = task
        let result = await task.value
        pending[url] = nil
        let cost = result.image.map { Int($0.size.width * $0.size.height * $0.scale * $0.scale * 4) } ?? 0
        cache.setObject(Entry(result), forKey: url.absoluteString as NSString, cost: cost)
        return result
    }
}

actor ExcerptService {
    static let shared = ExcerptService()
    private struct Entry: Codable { let excerpt: String?; let date: Date }
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpMaximumConnectionsPerHost = 2
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }
    func excerpt(for url: URL) async -> String? {
        guard (try? LinkRules.validatedURL(url.absoluteString)) != nil else { return nil }
        let directory = Configuration.directory.appendingPathComponent("Excerpts", isDirectory: true)
        let file = directory.appendingPathComponent(MetadataService.cacheKey(url) + ".json")
        if let data = try? Data(contentsOf: file), let entry = try? JSONDecoder().decode(Entry.self, from: data), Date().timeIntervalSince(entry.date) < (entry.excerpt == nil ? 300 : 604_800) { return entry.excerpt }
        var excerpt: String?
        do {
            var request = URLRequest(url: url)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  ["text/html", "application/xhtml+xml"].contains(response.mimeType?.lowercased() ?? "") else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                if data.count >= 524_288 { break }
            }
            if let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) { excerpt = ArticleExcerpt.extract(from: html) }
        } catch { /* A missing preview never prevents reading or saving a link. */ }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var cacheDirectory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? cacheDirectory.setResourceValues(values)
        if let data = try? JSONEncoder().encode(Entry(excerpt: excerpt, date: Date())) { try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let ordered = files.sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for old in ordered.dropFirst(200) { try? FileManager.default.removeItem(at: old) }
        return excerpt
    }
}
