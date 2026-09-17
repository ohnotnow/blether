import Foundation

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    static func install(_ handler: @escaping Handler) {
        URLProtocolStubRegistry.shared.install(handler)
    }

    static func reset() {
        URLProtocolStubRegistry.shared.reset()
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let handledRequest = requestWithMaterializedBody(request)
            let (response, data) = try URLProtocolStubRegistry.shared.response(for: handledRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func requestWithMaterializedBody(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let readCount = stream.read(buffer, maxLength: bufferSize)
            guard readCount > 0 else { break }
            data.append(buffer, count: readCount)
        }

        var materialized = request
        materialized.httpBodyStream = nil
        materialized.httpBody = data
        return materialized
    }
}

private final class URLProtocolStubRegistry: @unchecked Sendable {
    static let shared = URLProtocolStubRegistry()

    private let lock = NSLock()
    private var handler: URLProtocolStub.Handler?

    func install(_ handler: @escaping URLProtocolStub.Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        let handler = self.handler
        lock.unlock()

        guard let handler else { throw URLError(.resourceUnavailable) }
        return try handler(request)
    }
}
