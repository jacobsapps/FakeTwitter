import Foundation

enum AppEnvironment {
    static let serverBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["FAKE_TWITTER_SERVER_URL"],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }()
}
