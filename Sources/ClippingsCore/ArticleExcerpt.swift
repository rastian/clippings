import Foundation

/// A best-effort preview of public HTML. It never runs page scripts or replaces a user's description.
public enum ArticleExcerpt {
    public static func extract(from html: String) -> String? {
        let source = String(html.prefix(524_288))
        let cleaned = replacing(#"(?is)<!--.*?-->|<(script|style|nav|header|footer|aside|noscript|form)\b[^>]*>.*?</\1\s*>"#, in: source, with: " ")
        for tag in ["article", "main"] {
            if let content = captures("(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)\\s*>", in: cleaned).first?.first {
                let paragraphs = captures(#"(?is)<p\b[^>]*>(.*?)</p\s*>"#, in: content)
                    .compactMap { $0.first }.map(plainText).filter { $0.count >= 40 }
                if !paragraphs.isEmpty { return preview(paragraphs.prefix(3).joined(separator: " ")) }
            }
        }
        var descriptions: [String: String] = [:]
        for tag in captures(#"(?is)<meta\b([^>]+)>"#, in: source).compactMap({ $0.first }) {
            var attributes: [String: String] = [:]
            for match in captures(#"(?is)([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, in: tag) {
                attributes[match[0].lowercased()] = match.dropFirst().first { !$0.isEmpty } ?? ""
            }
            let name = (attributes["property"] ?? attributes["name"] ?? "").lowercased()
            if let text = attributes["content"], !text.isEmpty { descriptions[name] = plainText(text) }
        }
        for key in ["og:description", "description", "twitter:description"] {
            if let text = descriptions[key], !text.isEmpty { return preview(text) }
        }
        return nil
    }

    public static func preview(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, _, _, stop in
            if let sentence { sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if sentences.count == 2 { stop = true }
        }
        let result = sentences.isEmpty ? text : sentences.joined(separator: " ")
        guard result.count > 360 else { return result }
        let prefix = String(result.prefix(357))
        let boundary = prefix.lastIndex(where: { $0.isWhitespace }) ?? prefix.endIndex
        return String(prefix[..<boundary]) + "…"
    }

    private static func plainText(_ html: String) -> String {
        var text = replacing(#"(?is)<[^>]+>"#, in: html, with: " ")
        let entities = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " ", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "ndash": "–", "mdash": "—", "hellip": "…"]
        for match in captures(#"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#, in: text) {
            let key = match[0]
            var value = entities[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x")
                if let number = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) { value = String(scalar) }
            }
            if let value { text = text.replacingOccurrences(of: "&\(key);", with: value) }
        }
        return replacing(#"\s+"#, in: text, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func captures(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (1..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
        }
    }
    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: replacement)
    }
}
