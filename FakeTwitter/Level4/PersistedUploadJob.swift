import Foundation
import SwiftData

enum UploadJobState: String, Codable {
    case pending
    case uploading
    case succeeded
    case failed
}

@Model
final class PersistedUploadJob {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var attempts: Int
    var lastError: String?
    var stateRaw: String

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        attempts: Int = 0,
        lastError: String? = nil,
        state: UploadJobState = .pending
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attempts = attempts
        self.lastError = lastError
        self.stateRaw = state.rawValue
    }

    var state: UploadJobState {
        get { UploadJobState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }
}
