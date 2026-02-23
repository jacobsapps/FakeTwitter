import Foundation

/// Bridges background URLSession upload task events back into async/await continuations.
final class BackgroundSessionCoordinator: NSObject {
    static let shared = BackgroundSessionCoordinator()
    static let backgroundSessionIdentifier = "com.jacob.fakeTwitter.level3.background"

    typealias ProgressHandler = @MainActor (Double) -> Void

    private let lockQueue = DispatchQueue(label: "FakeTwitter.Level3BackgroundCoordinator")
    private var continuations: [Int: CheckedContinuation<HTTPURLResponse, Error>] = [:]
    private var progressHandlers: [Int: ProgressHandler] = [:]
    private var temporaryFiles: [Int: URL] = [:]
    private var systemCompletionHandler: (() -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func setSystemCompletionHandler(_ completion: @escaping () -> Void) {
        lockQueue.async {
            self.systemCompletionHandler = completion
        }
    }

    func uploadChunk(
        request: URLRequest,
        fromFile fileURL: URL,
        progress: @escaping ProgressHandler
    ) async throws -> HTTPURLResponse {
        _ = session

        let task = session.uploadTask(with: request, fromFile: fileURL)

        return try await withCheckedThrowingContinuation { continuation in
            lockQueue.async {
                self.continuations[task.taskIdentifier] = continuation
                self.progressHandlers[task.taskIdentifier] = progress
                self.temporaryFiles[task.taskIdentifier] = fileURL
                task.resume()
            }
        }
    }

    private func complete(taskIdentifier: Int, result: Result<HTTPURLResponse, Error>) {
        lockQueue.async {
            let continuation = self.continuations.removeValue(forKey: taskIdentifier)
            self.progressHandlers.removeValue(forKey: taskIdentifier)
            if let fileURL = self.temporaryFiles.removeValue(forKey: taskIdentifier) {
                try? FileManager.default.removeItem(at: fileURL)
            }

            guard let continuation else { return }
            switch result {
            case .success(let response):
                continuation.resume(returning: response)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

extension BackgroundSessionCoordinator: URLSessionTaskDelegate, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progressValue: Double
        if totalBytesExpectedToSend > 0 {
            progressValue = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        } else {
            progressValue = 0
        }

        var handler: ProgressHandler?
        lockQueue.sync {
            handler = progressHandlers[task.taskIdentifier]
        }

        if let handler {
            Task { @MainActor in
                handler(progressValue)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(taskIdentifier: task.taskIdentifier, result: .failure(error))
            return
        }

        guard let response = task.response as? HTTPURLResponse else {
            complete(taskIdentifier: task.taskIdentifier, result: .failure(HTTPClientError.invalidResponse))
            return
        }

        guard (200...299).contains(response.statusCode) else {
            let error = TweetUploadError.uploadFailed("Chunk upload failed with HTTP \(response.statusCode).")
            complete(taskIdentifier: task.taskIdentifier, result: .failure(error))
            return
        }

        complete(taskIdentifier: task.taskIdentifier, result: .success(response))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lockQueue.async {
            self.systemCompletionHandler?()
            self.systemCompletionHandler = nil
        }
    }
}
