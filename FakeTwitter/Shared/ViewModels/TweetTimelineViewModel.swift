import Foundation
import Combine

enum ComposerAlert: Identifiable {
    case error(id: UUID, message: String)
    case manualRetry(id: UUID, message: String)

    var id: UUID {
        switch self {
        case .error(let id, _):
            return id
        case .manualRetry(let id, _):
            return id
        }
    }
}

@MainActor
final class TweetTimelineViewModel: ObservableObject {
    @Published var tweets: [Tweet] = []
    @Published var composerText: String = ""
    @Published var isLoadingFeed = false
    @Published var isPosting = false
    @Published var selectedRetryStrategy: RetryStrategy = .exponentialBackoff
    @Published var selectedVideoURL: URL?
    @Published var selectedVideoLabel = "No video selected"
    @Published var uploadProgress: Double = 0
    @Published var showUploadProgress = false
    @Published var statusMessage: String?
    @Published var alert: ComposerAlert?

    let configuration: TweetTimelineConfiguration

    private let service: any TweetUploadService
    private var pendingManualRetry: (text: String, videoURL: URL?)?

    init(service: any TweetUploadService) {
        self.service = service
        self.configuration = service.configuration
    }

    func loadTimeline() async {
        isLoadingFeed = true
        tweets = await service.fetchTweets()
        statusMessage = await service.statusSummary()
        isLoadingFeed = false
    }

    func setSelectedVideo(url: URL) {
        selectedVideoURL = url
        selectedVideoLabel = url.lastPathComponent
    }

    func clearVideo() {
        selectedVideoURL = nil
        selectedVideoLabel = "No video selected"
    }

    func postTapped() async {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            alert = .error(id: UUID(), message: "Write something before posting.")
            return
        }

        await submit(text: trimmed, videoURL: selectedVideoURL)
    }

    func retryManualPost() async {
        guard let pendingManualRetry else { return }
        await submit(text: pendingManualRetry.text, videoURL: pendingManualRetry.videoURL)
    }

    private func submit(text: String, videoURL: URL?) async {
        isPosting = true
        showUploadProgress = configuration.supportsVideo
        uploadProgress = configuration.supportsVideo ? 0.01 : 0

        do {
            try await service.postTweet(
                text: text,
                videoURL: videoURL,
                strategy: selectedRetryStrategy,
                progress: { [weak self] value in
                    self?.uploadProgress = value
                    self?.showUploadProgress = true
                }
            )
            pendingManualRetry = nil
            composerText = ""
            if configuration.supportsVideo {
                clearVideo()
            }
            print("✅ \(configuration.levelTag) post flow finished")
        } catch let error as TweetUploadError {
            handle(error: error, text: text, videoURL: videoURL)
        } catch {
            alert = .error(id: UUID(), message: error.localizedDescription)
        }

        isPosting = false
        showUploadProgress = false
        tweets = await service.fetchTweets()
        statusMessage = await service.statusSummary()
    }

    private func handle(error: TweetUploadError, text: String, videoURL: URL?) {
        switch error {
        case .manualRetrySuggested(let message):
            pendingManualRetry = (text: text, videoURL: videoURL)
            alert = .manualRetry(id: UUID(), message: message)
        case .validation(let message):
            alert = .error(id: UUID(), message: message)
        case .uploadFailed(let message):
            alert = .error(id: UUID(), message: message)
        }
    }
}
