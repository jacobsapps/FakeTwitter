import SwiftUI
import AVKit

struct TweetTimelineScreen: View {
    @StateObject private var viewModel: TweetTimelineViewModel
    @State private var bundledVideoPlayer: AVPlayer?

    private let bundledVideoDisplayName = "never_gonna_give_you_up.mp4"

    init(service: any TweetUploadService) {
        _viewModel = StateObject(wrappedValue: TweetTimelineViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    composerCard

                    if let backgroundMessage = viewModel.backgroundCompletionMessage {
                        Text(backgroundMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    if viewModel.isLoadingFeed {
                        ProgressView("Loading timeline...")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    if viewModel.tweets.isEmpty, !viewModel.isLoadingFeed {
                        ContentUnavailableView(
                            "No tweets yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Post from this level to watch behavior differences.")
                        )
                        .padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.tweets) { tweet in
                                TweetRow(tweet: tweet)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle(viewModel.configuration.title)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.loadTimeline()
            }
        }
        .task {
            await viewModel.loadTimeline()
            configureBundledVideoIfNeeded()
        }
        .alert(item: $viewModel.alert) { alert in
            switch alert {
            case .error(_, let message):
                return Alert(
                    title: Text("Upload Error"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .manualRetry(_, let message):
                return Alert(
                    title: Text("Retry Upload?"),
                    message: Text(message),
                    primaryButton: .default(Text("Retry"), action: {
                        Task { await viewModel.retryManualPost() }
                    }),
                    secondaryButton: .cancel(Text("Cancel"))
                )
            }
        }
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compose")
                .font(.headline)

            TextField("What’s happening?", text: $viewModel.composerText, axis: .vertical)
                .lineLimit(4, reservesSpace: true)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if viewModel.configuration.showsRetrySelector {
                Picker("Retry mode", selection: $viewModel.selectedRetryStrategy) {
                    ForEach(RetryStrategy.allCases) { strategy in
                        Text(levelRetryLabel(for: strategy)).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Cap retries", isOn: $viewModel.capRetriesEnabled)
                    .font(.subheadline)
                    .disabled(viewModel.selectedRetryStrategy == .manual)

                Toggle("Use idempotency key", isOn: $viewModel.useIdempotencyKeyEnabled)
                    .font(.subheadline)
            }

            if viewModel.configuration.supportsVideo {
                bundledVideoSection
            }

            HStack(spacing: 12) {
                if viewModel.showUploadProgress {
                    Gauge(value: viewModel.uploadProgress, in: 0...1) {
                        Text("Upload")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.blue)
                    .frame(width: 44, height: 44)
                }

                Spacer()

                Button {
                    Task { await viewModel.postTapped() }
                } label: {
                    Text(viewModel.isPosting ? "Posting..." : "Post")
                        .frame(minWidth: 88)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isPosting)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }

    private var bundledVideoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Video selected")
                .font(.subheadline.weight(.semibold))

            Text(bundledVideoDisplayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let bundledVideoPlayer {
                VideoPlayer(player: bundledVideoPlayer)
                    .frame(width: 300)
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func levelRetryLabel(for strategy: RetryStrategy) -> String {
        if viewModel.configuration.levelTag == "level2" {
            return strategy.level2Label
        }
        return strategy.rawValue
    }

    private func configureBundledVideoIfNeeded() {
        guard viewModel.configuration.supportsVideo else { return }

        guard let videoURL = Bundle.main.url(
            forResource: "never_gonna_give_you_up",
            withExtension: "mp4"
        ) else {
            viewModel.alert = .error(id: UUID(), message: "Bundled video missing: \(bundledVideoDisplayName)")
            return
        }

        viewModel.setSelectedVideo(url: videoURL)

        if bundledVideoPlayer == nil {
            bundledVideoPlayer = AVPlayer(url: videoURL)
        }
    }
}

private struct TweetRow: View {
    let tweet: Tweet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("@fakeuser")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(tweet.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(tweet.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(tweet.level.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.blue)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
