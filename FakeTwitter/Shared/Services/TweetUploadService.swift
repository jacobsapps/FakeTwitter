import Foundation

enum RetryStrategy: String, CaseIterable, Identifiable {
    case automatic = "Automatic"
    case manual = "Manual"

    var id: String { rawValue }

    var level2Label: String {
        switch self {
        case .automatic:
            return "Exponential back-off"
        case .manual:
            return "User requested"
        }
    }
}

struct RetryOptions {
    var capRetries: Bool = false
    var useIdempotencyKey: Bool = false
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
        retryOptions: RetryOptions,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws
    func statusSummary() async -> String?
}

extension TweetUploadService {
    func statusSummary() async -> String? {
        nil
    }

    var onBackgroundUploadComplete: (() -> Void)? {
        get { nil }
        set {}
    }
}
