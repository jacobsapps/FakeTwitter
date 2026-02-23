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

    private let client: HTTPClient
    private var consecutiveCappedFailures = 0
    private var circuitOpenUntil: Date?

    init(client: HTTPClient) {
        self.client = client
    }

    func fetchTweets() async -> [Tweet] {
        await loadTimelineTweets(client: client)
    }

    func postTweet(
        text: String,
        videoURL _: URL?,
        strategy: RetryStrategy,
        retryOptions: RetryOptions,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let idempotencyKey = retryOptions.useIdempotencyKey ? UUID().uuidString : nil
        if let idempotencyKey {
            print("🧾 Level 2 idempotency key enabled: \(idempotencyKey)")
        }

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
                try await performOneAttempt(text: text, idempotencyKey: idempotencyKey)
                progress(1.0)
                print("🔁 Level 2 automatic backoff succeeded on attempt \(attempt)")
                return
            } catch Level2RetryFailure.transient(let message, let retryAfter) {
                print("⚠️ Transient failure attempt \(attempt): \(message)")
                guard attempt < maxAttempts else {
                    throw TweetUploadError.uploadFailed("Backoff retries exhausted after \(maxAttempts) attempts.")
                }
                let delay = retryAfter ?? min(8.0, pow(2.0, Double(attempt - 1)))
                try await sleep(seconds: delay)
            } catch Level2RetryFailure.terminal(let message) {
                throw TweetUploadError.uploadFailed(message)
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
                try await sleep(seconds: 0.75)
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
        var headers: [String: String] = [:]
        if let idempotencyKey {
            headers["Idempotency-Key"] = idempotencyKey
        }

        do {
            let (data, http) = try await client.postJSONRaw(
                path: "/level2/tweets",
                payload: PostTweetRequest(text: text),
                headers: headers
            )

            if (200...299).contains(http.statusCode) {
                return
            }

            let bodyText = String(data: data, encoding: .utf8) ?? ""
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
        } catch let error as Level2RetryFailure {
            throw error
        } catch {
            if let urlError = error as? URLError,
               urlError.code == .notConnectedToInternet || urlError.code == .timedOut {
                throw Level2RetryFailure.transient(message: urlError.localizedDescription, retryAfter: nil)
            }
            throw Level2RetryFailure.transient(message: error.localizedDescription, retryAfter: nil)
        }
    }

    private func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0.05, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
