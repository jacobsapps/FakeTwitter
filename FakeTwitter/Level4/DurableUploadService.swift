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

    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let engine: UploadJobEngine

    init(
        engine: UploadJobEngine,
        baseURL: URL,
        session: URLSession = .shared
    ) {
        self.engine = engine
        self.baseURL = baseURL
        self.session = session
        decoder.dateDecodingStrategy = .iso8601
    }

    func fetchTweets() async -> [Tweet] {
        do {
            let request = makeRequest(path: "tweets", method: "GET")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            return try decoder.decode(TweetsEnvelope.self, from: data).tweets
        } catch {
            print("⚠️ Failed to fetch tweets: \(error.localizedDescription)")
            return []
        }
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

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        return request
    }

    private func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private struct TweetsEnvelope: Codable {
        let tweets: [Tweet]
    }
}
