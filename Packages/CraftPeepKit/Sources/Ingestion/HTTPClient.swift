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

    public var description: String {
        switch self {
        case .invalidURL(let url): "Invalid URL: \(url)"
        case .insecureURL(let url): "Only https is allowed: \(url)"
        case .httpStatus(let code): "Server returned HTTP \(code)"
        case .tooLarge(let limit): "Response larger than \(limit / 1024) KB"
        case .notAFeed: "Response is not an RSS or Atom feed"
        case .malformed(let detail): "Could not parse response: \(detail)"
        case .network(let detail): "Network error: \(detail)"
        case .noAdapter(let kind): "No adapter for source kind \(kind.rawValue)"
        }
    }
}

public enum HTTPResult: Sendable, Equatable {
    case notModified
    case ok(data: Data, validators: HTTPValidators)
}

/// The one way ingestion touches the network, so tests can replace it.
public protocol HTTPClient: Sendable {
    func get(_ url: URL, validators: HTTPValidators?, accept: String, maxBytes: Int) async throws -> HTTPResult
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
        maxBytes: Int
    ) async throws -> HTTPResult {
        guard url.scheme?.lowercased() == "https" else {
            throw IngestionError.insecureURL(url.absoluteString)
        }

        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let etag = validators?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators?.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw IngestionError.network("Not an HTTP response")
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
