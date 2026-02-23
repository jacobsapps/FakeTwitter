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

    private let client: HTTPClient
    private let backgroundCoordinator: BackgroundSessionCoordinator
    private let offsetStore: UploadOffsetStore

    private let chunkSize: Int64 = 512 * 1024
    private let maxChunkRetries = 5

    init(
        client: HTTPClient,
        backgroundCoordinator: BackgroundSessionCoordinator? = nil,
        offsetStore: UploadOffsetStore? = nil
    ) {
        self.client = client
        self.backgroundCoordinator = backgroundCoordinator ?? .shared
        self.offsetStore = offsetStore ?? UploadOffsetStore()
    }

    func fetchTweets() async -> [Tweet] {
        await loadTimelineTweets(client: client)
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

        let startRequest = Level3StartRequest(
            text: text,
            filename: videoURL.lastPathComponent,
            totalBytes: fileSize
        )

        let startResponse: Level3StartResponse = try await client.postJSON(path: "/level3/uploads/start", payload: startRequest)

        var offset = max(startResponse.nextOffset, await offsetStore.offset(for: startResponse.sessionId))
        progress(Double(offset) / Double(fileSize))

        print("🚀 Level 3 upload started: session=\(startResponse.sessionId) total=\(fileSize)")

        while offset < fileSize {
            let remaining = fileSize - offset
            let currentChunkSize = min(chunkSize, remaining)
            var uploadedThisChunk = false

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

                    var request = URLRequest(url: client.url(path: "/level3/uploads/\(startResponse.sessionId)/chunk"))
                    request.httpMethod = "PUT"
                    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    request.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
                    request.setValue("\(fileSize)", forHTTPHeaderField: "Upload-Length")

                    let baseOffset = offset
                    let response = try await backgroundCoordinator.uploadChunk(request: request, fromFile: chunkFile.url) { chunkProgress in
                        let overall = (Double(baseOffset) + (chunkProgress * Double(chunkFile.byteCount))) / Double(fileSize)
                        progress(min(0.99, overall))
                    }

                    let nextOffsetHeader = response.value(forHTTPHeaderField: "Upload-Offset")
                    let nextOffset = Int64(nextOffsetHeader ?? "") ?? (offset + chunkFile.byteCount)
                    offset = max(nextOffset, offset + chunkFile.byteCount)
                    await offsetStore.set(offset: offset, for: startResponse.sessionId)

                    uploadedThisChunk = true
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
                    try await sleep(seconds: Double(attempt))
                }
            }

            if !uploadedThisChunk {
                throw TweetUploadError.uploadFailed("Resumable upload failed after \(maxChunkRetries) retries for one chunk.")
            }
        }

        _ = try await client.postJSONWithoutResponse(
            path: "/level3/uploads/\(startResponse.sessionId)/complete",
            payload: PostTweetRequest(text: text)
        )

        await offsetStore.clear(sessionId: startResponse.sessionId)
        progress(1.0)
        print("🎉 Level 3 upload complete for session \(startResponse.sessionId)")
    }

    private func fetchRemoteOffset(sessionId: String) async throws -> Int64 {
        let status: Level3StatusResponse = try await client.getJSON(path: "/level3/uploads/\(sessionId)")
        return status.offset
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

    private func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
