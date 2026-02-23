import Foundation

struct Tweet: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    let level: String
    let createdAt: Date
}

struct TweetsResponse: Codable {
    let tweets: [Tweet]
}

struct PostTweetRequest: Codable {
    let text: String
}

struct PostTweetResponse: Codable {
    let tweet: Tweet?
    let message: String?
}

struct Level3StartRequest: Codable {
    let text: String
    let filename: String
    let totalBytes: Int64
}

struct Level3StartResponse: Codable {
    let sessionId: String
    let nextOffset: Int64
}

struct Level3StatusResponse: Codable {
    let sessionId: String
    let offset: Int64
    let totalBytes: Int64
    let complete: Bool
}
