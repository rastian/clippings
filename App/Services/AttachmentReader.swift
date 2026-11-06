import Foundation
import UniformTypeIdentifiers

@MainActor
enum AttachmentReader {
    static func text(from provider: NSItemProvider, type: String) async -> String? {
        await withCheckedContinuation { continuation in
            let result = AttachmentResult(continuation)
            result.deadline = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(8)); result.finish(nil) } catch {}
            }
            if type == UTType.url.identifier, provider.canLoadObject(ofClass: NSURL.self) {
                result.progress = provider.loadObject(ofClass: NSURL.self) { item, _ in
                    let value = (item as? NSURL)?.absoluteString
                    Task { @MainActor in result.finish(value) }
                }
                return
            }
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                let value: String?
                if let url = item as? URL { value = url.absoluteString }
                else if let text = item as? String { value = text }
                else if let data = item as? Data, data.count <= 32_768 { value = String(data: data, encoding: .utf8) }
                else { value = nil }
                Task { @MainActor in result.finish(value) }
            }
        }
    }
}

@MainActor
private final class AttachmentResult {
    private var continuation: CheckedContinuation<String?, Never>?
    var deadline: Task<Void, Never>?
    var progress: Progress?
    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }
    func finish(_ text: String?) {
        let continuation = self.continuation; self.continuation = nil
        deadline?.cancel(); deadline = nil
        progress?.cancel(); progress = nil
        continuation?.resume(returning: text)
    }
}
