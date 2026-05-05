import Foundation

/// In-process URLProtocol that intercepts every request on a session it's
/// registered to and returns a canned response. Each test installs its own
/// handler closure; the static handler slot is guarded by an unfair lock so
/// it can be set from one queue and consumed from URLSession's worker queue.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _capturedRequests: [URLRequest] = []

    static func install(_ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
        _capturedRequests = []
    }

    static func uninstall() {
        lock.lock(); defer { lock.unlock() }
        _handler = nil
        _capturedRequests = []
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _capturedRequests
    }

    private static func currentHandler() -> Handler? {
        lock.lock(); defer { lock.unlock() }
        return _handler
    }

    private static func capture(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        _capturedRequests.append(request)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.currentHandler() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.capture(request)
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func ok(_ request: URLRequest, json: String) -> (HTTPURLResponse, Data) {
        response(request, status: 200, json: json)
    }

    static func response(_ request: URLRequest, status: Int, json: String, headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        var allHeaders = ["Content-Type": "application/json"]
        for (k, v) in headers { allHeaders[k] = v }
        let resp = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: allHeaders
        )!
        return (resp, Data(json.utf8))
    }
}
