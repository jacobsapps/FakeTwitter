import Foundation

@MainActor
/// Demonstrates chunked resumable uploads with background URLSession tasks per chunk.
/// Note: in this sample, the next chunk is scheduled by app code after the prior chunk finishes.
/// If the app is suspended between chunks, continuation waits until the app is active again.
final class ResumableBackgroundUploadService: TweetUploadService {
    let configuration = TweetTimelineConfiguration(
        title: "Resumable + Background",
        levelTag: "level3",
        supportsVideo: true,
        showsRetrySelector: false
    )

    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let backgroundCoordinator: BackgroundSessionCoordinator
    private let offsetStore: UploadOffsetStore

    var onBackgroundUploadComplete: (() -> Void)? {
        didSet { backgroundCoordinator.onBackgroundUploadsFinished = onBackgroundUploadComplete }
    }

    private let chunkSize: Int64 = 512 * 1024
    private let maxChunkRetries = 5

    init(
        baseURL: URL,
        session: URLSession = .shared,
        backgroundCoordinator: BackgroundSessionCoordinator? = nil,
        offsetStore: UploadOffsetStore? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.backgroundCoordinator = backgroundCoordinator ?? .shared
        self.offsetStore = offsetStore ?? UploadOffsetStore()
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
        videoURL: URL?,
        strategy _: RetryStrategy,
        retryOptions _: RetryOptions,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard let videoURL else {
            throw TweetUploadError.validation("Level 3 requires selecting a video before posting.")
        }

        let fileSize = try fileByteSize(for: videoURL)
        guard fileSize > 0 else {
            throw TweetUploadError.validation("Selected video is empty.")
        }

        let startResponse = try await startUploadSession(
            text: text,
            filename: videoURL.lastPathComponent,
            totalBytes: fileSize
        )

        var offset = max(startResponse.nextOffset, await offsetStore.offset(for: startResponse.sessionId))
        progress(Double(offset) / Double(fileSize))

        print("🚀 Level 3 upload started: session=\(startResponse.sessionId) total=\(fileSize)")

        while offset < fileSize {
            let remaining = fileSize - offset
            let currentChunkSize = min(chunkSize, remaining)

            for attempt in 1...maxChunkRetries {
                do {
                    let chunkFile = try temporaryChunkFile(
                        sourceVideoURL: videoURL,
                        offset: offset,
                        length: Int(currentChunkSize)
                    )
                    guard chunkFile.byteCount > 0 else {
                        throw TweetUploadError.uploadFailed("Failed to read chunk bytes from selected video.")
                    }

                    let request = makeChunkRequest(
                        sessionId: startResponse.sessionId,
                        offset: offset,
                        totalBytes: fileSize
                    )

                    let baseOffset = offset
                    let response = try await backgroundCoordinator.uploadChunk(request: request, fromFile: chunkFile.url) { chunkProgress in
                        let overall = (Double(baseOffset) + (chunkProgress * Double(chunkFile.byteCount))) / Double(fileSize)
                        progress(min(0.99, overall))
                    }

                    let nextOffset = parseNextOffset(
                        from: response,
                        fallbackOffset: offset + chunkFile.byteCount
                    )
                    offset = max(nextOffset, offset + chunkFile.byteCount)
                    await offsetStore.set(offset: offset, for: startResponse.sessionId)

                    print("📦 Chunk uploaded. offset=\(offset)/\(fileSize)")
                    break
                } catch {
                    print("🧯 Chunk failed at offset \(offset), attempt \(attempt): \(error.localizedDescription)")

                    if attempt >= maxChunkRetries {
                        throw TweetUploadError.uploadFailed("Resumable upload failed after \(maxChunkRetries) retries for one chunk.")
                    }

                    let remoteOffset = try await fetchRemoteOffset(sessionId: startResponse.sessionId)
                    offset = max(offset, remoteOffset)
                    await offsetStore.set(offset: offset, for: startResponse.sessionId)
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                }
            }
        }

        try await completeUpload(sessionId: startResponse.sessionId, text: text)

        await offsetStore.clear(sessionId: startResponse.sessionId)
        progress(1.0)
        print("🎉 Level 3 upload complete for session \(startResponse.sessionId)")
    }

    private func fetchRemoteOffset(sessionId: String) async throws -> Int64 {
        let request = makeRequest(path: "level3/uploads/\(sessionId)", method: "GET")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TweetUploadError.uploadFailed("Invalid server response while checking upload offset.")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TweetUploadError.uploadFailed("Request failed with HTTP \(http.statusCode). \(bodyText)")
        }
        let status = try decoder.decode(Level3StatusBody.self, from: data)
        return status.offset
    }

    /// Snippet-friendly start endpoint for resumable uploads.
    private func startUploadSession(text: String, filename: String, totalBytes: Int64) async throws -> Level3StartBody {
        var request = makeRequest(path: "level3/uploads/start", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Level3StartRequestBody(text: text, filename: filename, totalBytes: totalBytes))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TweetUploadError.uploadFailed("Invalid server response while starting upload.")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TweetUploadError.uploadFailed("Request failed with HTTP \(http.statusCode). \(bodyText)")
        }
        return try decoder.decode(Level3StartBody.self, from: data)
    }

    private func completeUpload(sessionId: String, text: String) async throws {
        var request = makeRequest(path: "level3/uploads/\(sessionId)/complete", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Level3CompleteBody(text: text))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TweetUploadError.uploadFailed("Invalid server response while finalizing upload.")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TweetUploadError.uploadFailed("Request failed with HTTP \(http.statusCode). \(bodyText)")
        }
    }

    private func fileByteSize(for fileURL: URL) throws -> Int64 {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func temporaryChunkFile(sourceVideoURL: URL, offset: Int64, length: Int) throws -> (url: URL, byteCount: Int64) {
        let handle = try FileHandle(forReadingFrom: sourceVideoURL)
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: length) ?? Data()

        let chunkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk-\(UUID().uuidString)")
            .appendingPathExtension("bin")

        try data.write(to: chunkURL, options: [.atomic])
        return (url: chunkURL, byteCount: Int64(data.count))
    }

    /// Snippet-friendly chunk request for resumable uploads.
private func makeChunkRequest(sessionId: String, offset: Int64, totalBytes: Int64) -> URLRequest {
    var request = URLRequest(url: url("level3/uploads/\(sessionId)/chunk"))
    request.httpMethod = "PUT"
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
    request.setValue("\(totalBytes)", forHTTPHeaderField: "Upload-Length")
    return request
}

    private func parseNextOffset(from response: HTTPURLResponse, fallbackOffset: Int64) -> Int64 {
        let headerValue = response.value(forHTTPHeaderField: "Upload-Offset")
        return Int64(headerValue ?? "") ?? fallbackOffset
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

    private struct Level3StartRequestBody: Codable {
        let text: String
        let filename: String
        let totalBytes: Int64
    }

    private struct Level3StartBody: Codable {
        let sessionId: String
        let nextOffset: Int64
    }

    private struct Level3StatusBody: Codable {
        let sessionId: String
        let offset: Int64
        let totalBytes: Int64
        let complete: Bool
    }

    private struct Level3CompleteBody: Codable {
        let text: String
    }
}
