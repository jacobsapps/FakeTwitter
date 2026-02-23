import SwiftUI

struct ContentView: View {
    let level1Service: any TweetUploadService
    let level2Service: any TweetUploadService
    let level3Service: any TweetUploadService
    let level4Service: any TweetUploadService

    var body: some View {
        TabView {
            TweetTimelineScreen(service: level1Service)
                .tabItem {
                    Label("Level 1", systemImage: "1.circle")
                }

            TweetTimelineScreen(service: level2Service)
                .tabItem {
                    Label("Level 2", systemImage: "2.circle")
                }

            TweetTimelineScreen(service: level3Service)
                .tabItem {
                    Label("Level 3", systemImage: "3.circle")
                }

            TweetTimelineScreen(service: level4Service)
                .tabItem {
                    Label("Level 4", systemImage: "4.circle")
                }
        }
    }
}
