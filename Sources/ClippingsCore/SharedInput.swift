import Foundation

public enum SharedInput {
    /// Prefer explicit URL attachments; text shares may include a caption around the URL.
    public static func url(in text: String) throws -> URL {
        guard text.utf8.count <= 32_768 else { throw ClippingsError.invalidURL }
        if let url = try? LinkRules.validatedURL(text) { return url }
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, let valid = try? LinkRules.validatedURL(url.absoluteString) { return valid }
        }
        throw ClippingsError.invalidURL
    }
}
