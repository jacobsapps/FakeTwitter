import Foundation

enum RetryStrategy: String, CaseIterable, Identifiable {
    case exponentialBackoff = "Backoff"
    case cappedRetries = "Capped"
    case manualRetry = "Manual"
    case idempotencyKey = "Idempotent"

    var id: String { rawValue }
}

struct TweetTimelineConfiguration {
    let title: String
    let levelTag: String
    let supportsVideo: Bool
    let showsRetrySelector: Bool
}

enum TweetUploadError: LocalizedError {
    case validation(String)
    case manualRetrySuggested(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .validation(let message):
            return message
        case .manualRetrySuggested(let message):
            return message
        case .uploadFailed(let message):
            return message
        }
    }
}

@MainActor
/// Contract for one upload strategy tab.
protocol TweetUploadService: AnyObject {
    var configuration: TweetTimelineConfiguration { get }
    func fetchTweets() async -> [Tweet]
    /// Unified posting contract used by the shared UI.
    /// Individual levels may ignore fields they do not need.
    func postTweet(
        text: String,
        videoURL: URL?,
        strategy: RetryStrategy,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws
    func statusSummary() async -> String?
}

extension TweetUploadService {
    func statusSummary() async -> String? {
        nil
    }
}
