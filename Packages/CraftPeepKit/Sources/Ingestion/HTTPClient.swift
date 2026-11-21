import Domain
import Foundation

public enum IngestionError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidURL(String)
    /// Plain HTTP and every non-web scheme are refused.
    case insecureURL(String)
    case httpStatus(Int)
    case tooLarge(limitBytes: Int)
    /// The response was not RSS, Atom or RDF (often an HTML error page).
    case notAFeed
    case malformed(String)
    case network(String)
    case noAdapter(SourceKind)
    /// The feed redirected to a plain-http address, which is only followed when the user allows it.
    case insecureRedirect(host: String)

    /// Starts the message for `insecureRedirect`, so the interface can offer the way out.
    public static let insecureRedirectMessage = "The feed has moved to an insecure http address"

    public var description: String {
        switch self {
        case .invalidURL(let url): "Invalid URL: \(url)"
        case .insecureURL(let url): "Only https is allowed for this feed: \(url). Allow plain http for it to fetch it."
        case .httpStatus(let code): Self.describe(status: code)
        case .tooLarge(let limit): "Response larger than \(limit / 1024) KB"
        case .notAFeed: "Response is not an RSS, Atom or JSON feed"
        case .malformed(let detail): "Could not parse response: \(detail)"
        case .network(let detail): "Network error: \(detail)"
        case .noAdapter(let kind): "No adapter for source kind \(kind.rawValue)"
        case .insecureRedirect(let host): "\(Self.insecureRedirectMessage) (\(host)). Allow plain http for this feed to follow it."
        }
    }

    /// Plain words for the statuses feeds actually return, saying whether trying again can help.
    static func describe(status code: Int) -> String {
        switch code {
        case 404: "The feed was not found at this address (HTTP 404). Some sites also answer 404 to apps they block."
        case 410: "The publisher has removed this feed (HTTP 410)."
        case 401, 403: "The site refused access to the feed (HTTP \(code))."
        case 429: "The site is limiting or blocking feed readers (HTTP 429). CraftPeep will try again less often."
        case 500...599: "The site had a problem (HTTP \(code)). This is usually temporary; CraftPeep will try again."
        default: "Server returned HTTP \(code)"
        }
    }
}

public enum HTTPResult: Sendable, Equatable {
    case notModified
    case ok(data: Data, validators: HTTPValidators)
}

/// The one way ingestion touches the network, so tests can replace it.
public protocol HTTPClient: Sendable {
    /// `allowInsecure` permits plain http for this request, including redirects to it. Only for a source
    /// the user has explicitly allowed.
    func get(_ url: URL, validators: HTTPValidators?, accept: String, maxBytes: Int, allowInsecure: Bool) async throws -> HTTPResult
}

extension HTTPClient {
    public func get(_ url: URL, validators: HTTPValidators?, accept: String, maxBytes: Int) async throws -> HTTPResult {
        try await get(url, validators: validators, accept: accept, maxBytes: maxBytes, allowInsecure: false)
    }
}

/// Stops a request from following a redirect to plain http unless that was allowed, and remembers where
/// it was going so the error can say so.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowInsecure: Bool
    private let lock = NSLock()
    private var target: URL?

    init(allowInsecure: Bool) {
        self.allowInsecure = allowInsecure
    }

    var blockedTarget: URL? { lock.withLock { target } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, url.scheme?.lowercased() != "https", !allowInsecure else { return request }
        lock.withLock { target = url }
        return nil
    }
}

/// URLSession-backed client: https only, no cookies, no cache, conditional requests,
/// and a size cap enforced while the body streams in.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(userAgent: String = "CraftPeep/0.1", timeout: TimeInterval = 20) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 3
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        session = URLSession(configuration: configuration)
    }

    public func get(
        _ url: URL,
        validators: HTTPValidators?,
        accept: String,
        maxBytes: Int,
        allowInsecure: Bool
    ) async throws -> HTTPResult {
        let scheme = url.scheme?.lowercased()
        guard scheme == "https" || (scheme == "http" && allowInsecure) else {
            throw IngestionError.insecureURL(url.absoluteString)
        }
        do {
            return try await fetch(url, validators: validators, accept: accept, maxBytes: maxBytes, allowInsecure: allowInsecure)
        } catch IngestionError.network(let detail) where allowInsecure && scheme == "https" {
            // An imported http feed is tried over https first. When the user has allowed http and the
            // site has no https at all, try the plain address once.
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw IngestionError.network(detail) }
            components.scheme = "http"
            guard let plain = components.url else { throw IngestionError.network(detail) }
            return try await fetch(plain, validators: validators, accept: accept, maxBytes: maxBytes, allowInsecure: true)
        }
    }

    private func fetch(_ url: URL, validators: HTTPValidators?, accept: String, maxBytes: Int, allowInsecure: Bool) async throws -> HTTPResult {
        let redirects = RedirectGuard(allowInsecure: allowInsecure)

        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let etag = validators?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
            guard let http = response as? HTTPURLResponse else {
                throw IngestionError.network("Not an HTTP response")
            }
            if let blocked = redirects.blockedTarget {
                throw IngestionError.insecureRedirect(host: blocked.host() ?? blocked.absoluteString)
            }
            if http.statusCode == 304 { return .notModified }
            guard (200..<300).contains(http.statusCode) else {
                throw IngestionError.httpStatus(http.statusCode)
            }
            if http.expectedContentLength > Int64(maxBytes) {
                throw IngestionError.tooLarge(limitBytes: maxBytes)
            }

            var data = Data()
            data.reserveCapacity(Int(max(0, min(http.expectedContentLength, Int64(maxBytes)))))
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes {
                    throw IngestionError.tooLarge(limitBytes: maxBytes)
                }
            }

            let fresh = HTTPValidators(
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified")
            )
            return .ok(data: data, validators: fresh)
        } catch let error as IngestionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // localizedDescription only: never the request, so headers cannot leak into logs.
            throw IngestionError.network(error.localizedDescription)
        }
    }
}
