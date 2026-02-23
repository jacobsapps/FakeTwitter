import Foundation
import SwiftData

/// Persistent Level 4 job runner that survives app relaunches via SwiftData.
actor UploadJobEngine {
    private let container: ModelContainer
    private let client: HTTPClient
    private var isProcessing = false

    init(container: ModelContainer, client: HTTPClient) {
        self.container = container
        self.client = client
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
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistedUploadJob>()

        do {
            let jobs = try context.fetch(descriptor)
            var recoveredCount = 0
            for job in jobs where job.state == .uploading {
                job.state = .pending
                job.updatedAt = .now
                recoveredCount += 1
            }
            try context.save()
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
        return jobs.filter { $0.state == .pending || $0.state == .uploading || $0.state == .failed }.count
    }

    private func processQueueIfNeeded() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        while let nextJob = fetchNextOutstandingJobSnapshot() {
            do {
                try updateJob(nextJob.id) { job in
                    job.state = .uploading
                    job.attempts += 1
                    job.lastError = nil
                    job.updatedAt = .now
                }

                _ = try await client.postJSONWithoutResponse(
                    path: "/level4/tweets",
                    payload: PostTweetRequest(text: nextJob.text)
                )

                try removeJob(nextJob.id)
                print("✅ Level 4 job completed and removed: \(nextJob.id)")
            } catch {
                try? updateJob(nextJob.id) { job in
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
              let job = jobs.first(where: { $0.state == .pending || $0.state == .failed || $0.state == .uploading }) else {
            return nil
        }

        return (id: job.id, text: job.text)
    }

    private func updateJob(_ jobID: UUID, mutate: (PersistedUploadJob) -> Void) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistedUploadJob>(predicate: #Predicate { job in
            job.id == jobID
        })

        guard let job = try context.fetch(descriptor).first else {
            return
        }

        mutate(job)
        try context.save()
    }

    private func removeJob(_ jobID: UUID) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistedUploadJob>(predicate: #Predicate { job in
            job.id == jobID
        })

        guard let job = try context.fetch(descriptor).first else {
            return
        }

        context.delete(job)
        try context.save()
    }
}
