import Foundation

@MainActor
/// Level 1: single-attempt fire-and-forget upload.
final class FireAndForgetUploadService: TweetUploadService {
    let configuration = TweetTimelineConfiguration(
        title: "Fire and Forget",
        levelTag: "level1",
        supportsVideo: false,
        showsRetrySelector: false
    )

    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURL: URL, session: URLSession = .shared) {
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
        progress(0.1)

        do {
            try await sendOneShotTweet(text: text)
            print("📮 Level 1 upload sent once")
        } catch {
            print("💥 Level 1 fire-and-forget failed: \(error.localizedDescription)")
            // Fire-and-forget intentionally does not surface an error to the user.
        }

        progress(1.0)
    }

    /// Snippet-friendly: one request, one attempt, no local retry.
    private func sendOneShotTweet(text: String) async throws {
        var request = makeRequest(path: "level1/tweets", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Level1PostBody(text: text))
        _ = try await session.data(for: request)
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        return request
    }

    private func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private struct Level1PostBody: Codable {
        let text: String
    }

    private struct TweetsEnvelope: Codable {
        let tweets: [Tweet]
    }
}
