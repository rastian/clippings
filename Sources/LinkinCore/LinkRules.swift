import Foundation

public enum LinkRules {
    public static func validatedURL(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: trimmed),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, host.contains("."),
              parts.user == nil, parts.password == nil else { throw LinkinError.invalidURL }
        parts.scheme = scheme; parts.host = host.lowercased()
        guard let url = parts.url else { throw LinkinError.invalidURL }
        return url
    }
    public static func canonical(_ input: String) throws -> String {
        let url = try validatedURL(input)
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw LinkinError.invalidURL }
        parts.fragment = nil
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        if parts.path.isEmpty { parts.path = "/" }
        return parts.string ?? url.absoluteString
    }
    public static func name(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw LinkinError.emptyName }
        return String(value.prefix(120))
    }
    public static func metadataTitle(_ title: String?, url: URL) -> String {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? (url.host() ?? url.absoluteString) : String(value.prefix(500))
    }
    public static func links(in state: Snapshot, zone: Zone, query: String = "", collection: String? = nil, oldestFirst: Bool = false) -> [Item] {
        let collections = state.visible(.collection, zone: zone)
        return state.visible(.link, zone: zone).filter { link in
            let collectionExists = collections.contains { $0.id == link["collection"] }
            let matchesCollection = collection == nil || link["collection"] == collection || (collection == "unfiled" && !collectionExists)
            let note = state.visible(.note).first { $0["link"] == link.key }?["text"] ?? ""
            let text = [link.title, link["url"], link["domain"], link["summary"], note,
                        collections.first { $0.id == link["collection"] }?.title ?? ""].joined(separator: " ")
            return matchesCollection && (query.isEmpty || text.localizedStandardContains(query))
        }.sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return oldestFirst ? $0.date < $1.date : $0.date > $1.date
        }
    }
    public static func unreadMentions(in state: Snapshot, userID: String) -> [Item] {
        state.visible(.mention).filter {
            $0["recipient"] == userID && $0["author"] != userID && $0["read"] != "true" &&
            state.items["\($0.zone.key)|\($0["link"])"]?.deleted == false
        }.sorted { $0.date > $1.date }
    }
    public static func shouldNotify(_ mention: Item, userID: String, notified: Set<String>) -> Bool {
        mention.kind == .mention && !mention.deleted && mention["recipient"] == userID &&
        mention["author"] != userID && mention["read"] != "true" && !notified.contains(mention.key)
    }
}
