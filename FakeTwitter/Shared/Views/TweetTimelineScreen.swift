import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers

struct TweetTimelineScreen: View {
    @StateObject private var viewModel: TweetTimelineViewModel
    @State private var selectedVideoItem: PhotosPickerItem?

    init(service: any TweetUploadService) {
        _viewModel = StateObject(wrappedValue: TweetTimelineViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    composerCard

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
            .refreshable {
                await viewModel.loadTimeline()
            }
        }
        .task {
            await viewModel.loadTimeline()
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let pickedMovie = try? await newItem.loadTransferable(type: PickedMovie.self) {
                    viewModel.setSelectedVideo(url: pickedMovie.url)
                    print("🎬 Picked video: \(pickedMovie.url.lastPathComponent)")
                } else {
                    viewModel.alert = .error(id: UUID(), message: "Failed to import selected video.")
                }
            }
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
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)
            }

            if viewModel.configuration.supportsVideo {
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
                        Label("Choose Video", systemImage: "video.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    HStack {
                        Text(viewModel.selectedVideoLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if viewModel.selectedVideoURL != nil {
                            Button("Clear") {
                                viewModel.clearVideo()
                                selectedVideoItem = nil
                            }
                            .font(.caption)
                        }
                    }
                }
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

private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
