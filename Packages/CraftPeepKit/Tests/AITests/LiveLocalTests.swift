import Foundation
import Testing
@testable import AI

/// Talks to an Ollama server on this Mac, if one is running. Costs nothing and sends nothing off the machine.
///   CRAFTPEEP_LIVE=1 swift test --filter LiveLocalTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRAFTPEEP_LIVE"] == "1"))
struct LiveLocalTests {
    @Test func realTransportReachesALocalServerAndMapsItsErrors() async throws {
        let provider = try OpenAICompatibleProvider(
            baseURL: ProviderConfiguration.defaultCompatibleBaseURL, model: "craftpeep-no-such-model",
            apiKey: nil, transport: URLSessionAITransport()
        )
        do {
            _ = try await provider.complete(AIRequest(feature: .connectionTest, system: "Reply OK.", user: "ping", maxOutputTokens: 16))
            Issue.record("a model that does not exist answered")
        } catch let error as ProviderError {
            print("LIVE local server replied: \(error)")
            #expect(error == .modelNotFound("craftpeep-no-such-model"))
        }
    }
}
