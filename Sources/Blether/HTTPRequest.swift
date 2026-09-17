import Foundation

/// A minimal HTTP/1.1 request: method, path, headers, body sized by Content-Length.
/// Chunked bodies are not supported and read as empty.
struct HTTPRequest {
    let method: String
    let path: String
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
        return HTTPRequest(method: head.method, path: head.path, headers: head.headers, body: body)
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
        let request = HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: Data())
        return (request, range.upperBound - data.startIndex)
    }
}
