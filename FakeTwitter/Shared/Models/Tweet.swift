import Foundation

struct Tweet: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    let level: String
    let createdAt: Date
}
