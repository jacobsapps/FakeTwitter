import Foundation

actor UploadOffsetStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.jacob.fakeTwitter.level3.uploadOffsets"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func offset(for sessionId: String) -> Int64 {
        Int64(loadOffsets()[sessionId] ?? 0)
    }

    func set(offset: Int64, for sessionId: String) {
        var offsets = loadOffsets()
        offsets[sessionId] = Int(offset)
        defaults.set(offsets, forKey: storageKey)
    }

    func clear(sessionId: String) {
        var offsets = loadOffsets()
        offsets.removeValue(forKey: sessionId)
        defaults.set(offsets, forKey: storageKey)
    }

    private func loadOffsets() -> [String: Int] {
        defaults.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    }
}
