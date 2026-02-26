import Foundation

private enum BackgroundUploadError: LocalizedError {
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Background upload returned an invalid response."
        }
    }
}

/// Bridges background URLSession upload task events back into async/await continuations.
@MainActor
final class BackgroundSessionCoordinator: NSObject {
    static let shared = BackgroundSessionCoordinator()
    static let backgroundSessionIdentifier = "com.jacob.fakeTwitter.level3.background"
    
    typealias ProgressHandler = @MainActor (Double) -> Void
    
    private var continuations: [Int: CheckedContinuation<HTTPURLResponse, Error>] = [:]
    private var progressHandlers: [Int: ProgressHandler] = [:]
    private var temporaryFiles: [Int: URL] = [:]
    private var systemCompletionHandler: (() -> Void)?
    var onBackgroundUploadsFinished: (() -> Void)?
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()
    
    func setSystemCompletionHandler(_ completion: @escaping () -> Void) {
        systemCompletionHandler = completion
    }
    
    func uploadChunk(
        request: URLRequest,
        fromFile fileURL: URL,
        progress: @escaping ProgressHandler
    ) async throws -> HTTPURLResponse {
        _ = session
        
        let task = session.uploadTask(with: request, fromFile: fileURL)
        
        return try await withCheckedThrowingContinuation { continuation in
            continuations[task.taskIdentifier] = continuation
            progressHandlers[task.taskIdentifier] = progress
            temporaryFiles[task.taskIdentifier] = fileURL
            task.resume()
        }
    }
    
    private func complete(taskIdentifier: Int, result: Result<HTTPURLResponse, Error>) {
        let continuation = continuations.removeValue(forKey: taskIdentifier)
        progressHandlers.removeValue(forKey: taskIdentifier)
        if let fileURL = temporaryFiles.removeValue(forKey: taskIdentifier) {
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

extension BackgroundSessionCoordinator: URLSessionTaskDelegate, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progressValue = totalBytesExpectedToSend > 0
        ? Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        : 0.0
        
        progressHandlers[task.taskIdentifier]?(progressValue)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            complete(taskIdentifier: task.taskIdentifier, result: .failure(error))
            return
        }
        
        guard let response = task.response as? HTTPURLResponse else {
            complete(taskIdentifier: task.taskIdentifier, result: .failure(BackgroundUploadError.invalidResponse))
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
        onBackgroundUploadsFinished?()
        systemCompletionHandler?()
        systemCompletionHandler = nil
    }
}
