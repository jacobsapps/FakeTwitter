import UIKit

final class FakeTwitterAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundSessionCoordinator.backgroundSessionIdentifier else {
            completionHandler()
            return
        }

        print("📬 Received background URLSession wake for \(identifier)")
        BackgroundSessionCoordinator.shared.setSystemCompletionHandler(completionHandler)
    }
}
