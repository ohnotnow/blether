import Foundation

/// A minimal HTTP/1.1 request: method, path, headers, body sized by Content-Length.
/// Chunked bodies are not supported and read as empty.
struct HTTPRequest {
    let method: String
    /// The request target without its query string.
    let path: String
    /// Percent-decoded query parameters; the first value wins for a repeated name.
    let query: [String: String]
    /// Keys are lowercased; use `header(_:)` for lookup.
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    /// Zero when the header is absent. Nil when it is present but not a non-negative integer,
    /// which the server answers with a 400 rather than trusting it.
    var declaredContentLength: Int? {
        guard let raw = header("content-length") else { return 0 }
        guard let length = Int(raw), length >= 0 else { return nil }
        return length
    }

    /// Nil until the request line, headers and the whole declared body have arrived.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let (head, bodyStart) = parseHead(data) else { return nil }
        guard let length = head.declaredContentLength, data.count - bodyStart >= length else { return nil }
        let body = data.subdata(in: bodyStart ..< bodyStart + length)
        return HTTPRequest(method: head.method, path: head.path, query: head.query, headers: head.headers, body: body)
    }

    /// "/hook?profile=Serious%20and%20stern" gives ("/hook", ["profile": "Serious and stern"]). A target
    /// URLComponents rejects is kept whole as the path, so the server answers 404 as it always did.
    static func splitTarget(_ target: String) -> (path: String, query: [String: String]) {
        guard let components = URLComponents(string: target) else { return (target, [:]) }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        return (components.path, query)
    }

    /// The request line and headers, with an empty body, plus the offset where the body starts.
    /// Nil until the blank line ending the headers has arrived, or if the request line is malformed.
    static func parseHead(_ data: Data) -> (request: HTTPRequest, bodyStart: Int)? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return nil }
        let headText = String(decoding: data[data.startIndex ..< range.lowerBound], as: UTF8.self)
        var lines = headText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let (path, query) = splitTarget(String(requestLine[1]))
        let request = HTTPRequest(method: String(requestLine[0]), path: path, query: query, headers: headers, body: Data())
        return (request, range.upperBound - data.startIndex)
    }
}
