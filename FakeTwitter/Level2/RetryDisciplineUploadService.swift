import Foundation

private enum Level2RetryFailure: Error {
    case transient(message: String, retryAfter: TimeInterval?)
    case terminal(message: String)
}

@MainActor
/// Demonstrates foreground retry discipline with selectable retry strategies.
final class RetryDisciplineUploadService: TweetUploadService {
    let configuration = TweetTimelineConfiguration(
        title: "Retry Discipline",
        levelTag: "level2",
        supportsVideo: false,
        showsRetrySelector: true
    )

    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var consecutiveCappedFailures = 0
    private var circuitOpenUntil: Date?

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
        strategy: RetryStrategy,
        retryOptions: RetryOptions,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let idempotencyKey = makeIdempotencyKey(enabled: retryOptions.useIdempotencyKey)

        switch strategy {
        case .automatic:
            if retryOptions.capRetries {
                try await runCappedCircuitMode(text: text, idempotencyKey: idempotencyKey, progress: progress)
            } else {
                try await runExponentialBackoff(text: text, idempotencyKey: idempotencyKey, progress: progress)
            }
        case .manual:
            try await runManualRetryMode(text: text, idempotencyKey: idempotencyKey, progress: progress)
        }
    }

    private func runExponentialBackoff(
        text: String,
        idempotencyKey: String?,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let maxAttempts = 5

        for attempt in 1...maxAttempts {
            progress(Double(attempt - 1) / Double(maxAttempts))
            do {
                var request = makeRequest(path: "level2/tweets", method: "POST")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let idempotencyKey {
                    request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
                }
                request.httpBody = try encoder.encode(Level2PostBody(text: text))

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw Level2RetryFailure.transient(message: "Invalid response.", retryAfter: nil)
                }

                if (200...299).contains(http.statusCode) {
                    progress(1.0)
                    print("🔁 Level 2 automatic backoff succeeded on attempt \(attempt)")
                    return
                }

                let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)

                if http.statusCode >= 500 || http.statusCode == 429 {
                    throw Level2RetryFailure.transient(
                        message: bodyText.isEmpty ? "Server unavailable." : bodyText,
                        retryAfter: retryAfter
                    )
                }

                throw Level2RetryFailure.terminal(
                    message: bodyText.isEmpty ? "Request failed with HTTP \(http.statusCode)." : bodyText
                )
            } catch Level2RetryFailure.transient(let message, let retryAfter) {
                print("⚠️ Transient failure attempt \(attempt): \(message)")
                guard attempt < maxAttempts else {
                    throw TweetUploadError.uploadFailed("Backoff retries exhausted after \(maxAttempts) attempts.")
                }
                let delay = exponentialBackoffDelay(attempt: attempt, serverRetryAfter: retryAfter)
                try await Task.sleep(for: .seconds(delay))
            } catch Level2RetryFailure.terminal(let message) {
                throw TweetUploadError.uploadFailed(message)
            } catch {
                if let urlError = error as? URLError,
                   urlError.code == .notConnectedToInternet || urlError.code == .timedOut {
                    guard attempt < maxAttempts else {
                        throw TweetUploadError.uploadFailed("Backoff retries exhausted after \(maxAttempts) attempts.")
                    }
                    let delay = exponentialBackoffDelay(attempt: attempt, serverRetryAfter: nil)
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
                throw TweetUploadError.uploadFailed(error.localizedDescription)
            }
        }
    }

    private func runCappedCircuitMode(
        text: String,
        idempotencyKey: String?,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        if let circuitOpenUntil, circuitOpenUntil > Date() {
            let remaining = Int(circuitOpenUntil.timeIntervalSinceNow.rounded(.up))
            throw TweetUploadError.uploadFailed("Circuit breaker is open. Try again in \(remaining)s.")
        }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            progress(Double(attempt - 1) / Double(maxAttempts))
            do {
                try await performOneAttempt(text: text, idempotencyKey: idempotencyKey)
                consecutiveCappedFailures = 0
                progress(1.0)
                print("🛡️ Level 2 capped automatic strategy succeeded")
                return
            } catch Level2RetryFailure.transient(let message, _) {
                print("🚧 Capped attempt \(attempt) failed: \(message)")
                guard attempt < maxAttempts else { break }
                try await Task.sleep(for: .seconds(0.75))
            } catch Level2RetryFailure.terminal(let message) {
                throw TweetUploadError.uploadFailed(message)
            }
        }

        consecutiveCappedFailures += 1
        if consecutiveCappedFailures >= 2 {
            circuitOpenUntil = Date().addingTimeInterval(15)
            consecutiveCappedFailures = 0
            throw TweetUploadError.uploadFailed("Circuit opened for 15 seconds after repeated failures.")
        }

        throw TweetUploadError.uploadFailed("Capped retries exhausted.")
    }

    private func runManualRetryMode(
        text: String,
        idempotencyKey: String?,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        progress(0.1)
        do {
            try await performOneAttempt(text: text, idempotencyKey: idempotencyKey)
            progress(1.0)
            print("🙋 Level 2 manual strategy succeeded on first try")
        } catch {
            throw TweetUploadError.manualRetrySuggested("Upload failed. Retry manually?")
        }
    }

    private func performOneAttempt(text: String, idempotencyKey: String?) async throws {
        do {
            let request = try makePostRequest(text: text, idempotencyKey: idempotencyKey)
            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw Level2RetryFailure.transient(message: "Invalid response.", retryAfter: nil)
            }

            if (200...299).contains(http.statusCode) {
                return
            }

            let bodyText = responseBodyText(data)
            let retryAfter = retryAfterSeconds(from: http)

            if isTransientHTTPStatus(http.statusCode) {
                throw Level2RetryFailure.transient(
                    message: bodyText.isEmpty ? "Server unavailable." : bodyText,
                    retryAfter: retryAfter
                )
            }

            throw Level2RetryFailure.terminal(
                message: bodyText.isEmpty ? "Request failed with HTTP \(http.statusCode)." : bodyText
            )
        } catch let error as Level2RetryFailure {
            throw error
        } catch {
            if isTransientNetworkError(error) {
                throw Level2RetryFailure.transient(message: error.localizedDescription, retryAfter: nil)
            }
            throw Level2RetryFailure.transient(message: error.localizedDescription, retryAfter: nil)
        }
    }

    private func makeIdempotencyKey(enabled: Bool) -> String? {
        guard enabled else { return nil }
        let key = UUID().uuidString
        print("🧾 Level 2 idempotency key enabled: \(key)")
        return key
    }

    private func exponentialBackoffDelay(attempt: Int, serverRetryAfter: TimeInterval?) -> TimeInterval {
        if let serverRetryAfter {
            return serverRetryAfter
        }
        return pow(2.0, Double(attempt - 1))
    }

    private func makePostRequest(text: String, idempotencyKey: String?) throws -> URLRequest {
        var request = makeRequest(path: "level2/tweets", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        request.httpBody = try encoder.encode(Level2PostBody(text: text))
        return request
    }

    private func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
    }

    private func responseBodyText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func isTransientHTTPStatus(_ statusCode: Int) -> Bool {
        statusCode >= 500 || statusCode == 429
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .notConnectedToInternet || urlError.code == .timedOut
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: url(path))
        request.httpMethod = method
        return request
    }

    private func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private struct Level2PostBody: Codable {
        let text: String
    }

    private struct TweetsEnvelope: Codable {
        let tweets: [Tweet]
    }
}
