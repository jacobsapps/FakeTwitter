import Foundation
import SwiftData

/// Persistent Level 4 job runner that survives app relaunches via SwiftData.
actor UploadJobEngine {
    private let container: ModelContainer
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private var isProcessing = false

    init(
        container: ModelContainer,
        baseURL: URL,
        session: URLSession = .shared
    ) {
        self.container = container
        self.baseURL = baseURL
        self.session = session
    }

    func enqueue(text: String) async {
        let context = ModelContext(container)
        let job = PersistedUploadJob(text: text, state: .pending)
        context.insert(job)

        do {
            try context.save()
            print("🗂️ Enqueued Level 4 job \(job.id)")
        } catch {
            print("💥 Failed to persist Level 4 job: \(error.localizedDescription)")
        }

        await processQueueIfNeeded()
    }

    func recoverAndProcessOutstandingJobs() async {
        do {
            let recoveredCount = try recoverUploadingJobsAsPending()
            print("🔄 Recovered \(recoveredCount) stuck Level 4 jobs")
        } catch {
            print("💥 Failed to recover Level 4 jobs: \(error.localizedDescription)")
        }

        await processQueueIfNeeded()
    }

    func outstandingCount() -> Int {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistedUploadJob>()

        let jobs = (try? context.fetch(descriptor)) ?? []
        return jobs.filter { isOutstanding($0.state) }.count
    }

    private func processQueueIfNeeded() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        while let nextJob = fetchNextOutstandingJobSnapshot() {
            do {
                try withJob(nextJob.id) { _, job in
                    job.state = .uploading
                    job.attempts += 1
                    job.lastError = nil
                    job.updatedAt = .now
                }

                try await submitLevel4Tweet(text: nextJob.text)

                try withJob(nextJob.id) { context, job in context.delete(job) }
                print("✅ Level 4 job completed and removed: \(nextJob.id)")
            } catch {
                try? withJob(nextJob.id) { _, job in
                    job.state = .failed
                    job.lastError = error.localizedDescription
                    job.updatedAt = .now
                }
                print("❌ Level 4 job failed \(nextJob.id): \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func fetchNextOutstandingJobSnapshot() -> (id: UUID, text: String)? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistedUploadJob>(sortBy: [SortDescriptor(\.createdAt)])

        guard let jobs = try? context.fetch(descriptor),
              let job = jobs.first(where: { isOutstanding($0.state) }) else {
            return nil
        }

        return (id: job.id, text: job.text)
    }

    private func recoverUploadingJobsAsPending() throws -> Int {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistedUploadJob>()
        let jobs = try context.fetch(descriptor)
        var recoveredCount = 0

        for job in jobs where job.state == .uploading {
            job.state = .pending
            job.updatedAt = .now
            recoveredCount += 1
        }

        try context.save()
        return recoveredCount
    }

    private func withJob(_ jobID: UUID, _ body: (ModelContext, PersistedUploadJob) -> Void) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistedUploadJob>(predicate: #Predicate { job in
            job.id == jobID
        })

        guard let job = try context.fetch(descriptor).first else { return }
        body(context, job)
        try context.save()
    }

    private func isOutstanding(_ state: UploadJobState) -> Bool {
        state == .pending || state == .uploading || state == .failed
    }

    /// Snippet-friendly durable job execution step.
    private func submitLevel4Tweet(text: String) async throws {
        var request = URLRequest(url: url("level4/tweets"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(Level4PostBody(text: text))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TweetUploadError.uploadFailed("Invalid response while running durable job.")
        }
        guard (200...299).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if bodyText.isEmpty {
                throw TweetUploadError.uploadFailed("Durable job failed with HTTP \(http.statusCode).")
            }
            throw TweetUploadError.uploadFailed(bodyText)
        }
    }

    private func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private struct Level4PostBody: Codable {
        let text: String
    }
}
