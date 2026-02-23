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

        let client = HTTPClient(baseURL: AppEnvironment.serverBaseURL)
        level1Service = FireAndForgetUploadService(client: client)
        level2Service = RetryDisciplineUploadService(client: client)
        level3Service = ResumableBackgroundUploadService(client: client)

        let engine = UploadJobEngine(container: modelContainer, client: client)
        level4Engine = engine
        level4Service = DurableUploadService(client: client, engine: engine)

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
