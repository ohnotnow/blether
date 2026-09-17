import Foundation

/// The one definition of what a valid extra request body is, shared by the client and the settings window.
enum ExtraBody {
    /// The parsed object, or nil when the text is not a JSON object. Blank and "{}" are valid and empty.
    static func parse(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any]
    }

    /// The parser's own words for why `text` is not an object, first line only, for the settings window.
    static func problem(_ text: String) -> String? {
        if parse(text) != nil { return nil }
        do {
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
            return object is [String: Any] ? nil : "top level is not an object"
        } catch {
            return (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
        }
    }
}
