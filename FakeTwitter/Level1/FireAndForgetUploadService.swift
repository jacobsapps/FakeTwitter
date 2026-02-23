import Foundation

@MainActor
/// Level 1: single-attempt fire-and-forget upload.
final class FireAndForgetUploadService: TweetUploadService {
    let configuration = TweetTimelineConfiguration(
        title: "Level 1 · Fire and Forget",
        levelTag: "level1",
        supportsVideo: false,
        showsRetrySelector: false
    )

    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchTweets() async -> [Tweet] {
        await fetchTweets(client: client)
    }

    func postTweet(
        text: String,
        videoURL _: URL?,
        strategy _: RetryStrategy,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        progress(0.1)

        let payload = PostTweetRequest(text: text)

        do {
            _ = try await client.postJSONWithoutResponse(path: "/level1/tweets", payload: payload)
            print("📮 Level 1 upload sent once")
        } catch {
            print("💥 Level 1 fire-and-forget failed: \(error.localizedDescription)")
            // Fire-and-forget intentionally does not surface an error to the user.
        }

        progress(1.0)
    }
}
