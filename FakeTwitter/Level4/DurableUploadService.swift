import Foundation

@MainActor
/// Level 4: enqueues a persistent upload job and lets the engine process it durably.
final class DurableUploadService: TweetUploadService {
    let configuration = TweetTimelineConfiguration(
        title: "Durable State Machine",
        levelTag: "level4",
        supportsVideo: false,
        showsRetrySelector: false
    )

    private let client: HTTPClient
    private let engine: UploadJobEngine

    init(client: HTTPClient, engine: UploadJobEngine) {
        self.client = client
        self.engine = engine
    }

    func fetchTweets() async -> [Tweet] {
        await loadTimelineTweets(client: client)
    }

    func postTweet(
        text: String,
        videoURL _: URL?,
        strategy _: RetryStrategy,
        retryOptions _: RetryOptions,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        progress(0.2)
        await engine.enqueue(text: text)
        progress(1.0)
    }

    func statusSummary() async -> String? {
        let outstanding = await engine.outstandingCount()
        return "Durable queue outstanding jobs: \(outstanding)"
    }
}
