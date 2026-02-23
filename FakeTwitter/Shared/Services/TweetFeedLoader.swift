import Foundation

func fetchTweets(client: HTTPClient) async -> [Tweet] {
    do {
        let response: TweetsResponse = try await client.getJSON(path: "/tweets")
        return response.tweets
    } catch {
        print("⚠️ Failed to fetch tweets: \(error.localizedDescription)")
        return []
    }
}
