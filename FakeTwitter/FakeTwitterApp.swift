import SwiftUI
import SwiftData

@main
struct FakeTwitterApp: App {
    @UIApplicationDelegateAdaptor(FakeTwitterAppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let level4Engine: UploadJobEngine

    private let level1Service: FireAndForgetUploadService
    private let level2Service: RetryDisciplineUploadService
    private let level3Service: ResumableBackgroundUploadService
    private let level4Service: DurableUploadService

    init() {
        let schema = Schema([PersistedUploadJob.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }

        // Eagerly create the background session so it can receive system wake callbacks.
        _ = BackgroundSessionCoordinator.shared

        let baseURL = AppEnvironment.serverBaseURL
        level1Service = FireAndForgetUploadService(baseURL: baseURL)
        level2Service = RetryDisciplineUploadService(baseURL: baseURL)
        level3Service = ResumableBackgroundUploadService(baseURL: baseURL)

        let engine = UploadJobEngine(container: modelContainer, baseURL: baseURL)
        level4Engine = engine
        level4Service = DurableUploadService(engine: engine, baseURL: baseURL)

        Task {
            await engine.recoverAndProcessOutstandingJobs()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                level1Service: level1Service,
                level2Service: level2Service,
                level3Service: level3Service,
                level4Service: level4Service
            )
        }
        .modelContainer(modelContainer)
    }
}
