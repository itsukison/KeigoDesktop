import Foundation

/// On-device rewrite history, and the only source the ホーム page's numbers have.
///
/// One JSON file under Application Support. Entries are newest-first so trimming to
/// `capacity` is a tail drop, and the whole payload is small enough (≤ 500 rows) that
/// keeping it in memory and rewriting the file on each mutation is cheaper than any
/// incremental scheme would be to get right.
///
/// **This file holds the user's actual text, in the clear.** That is what makes the
/// history list useful, and it is also why `isEnabled` exists and why the file is
/// written `0o600` — the app reads from arbitrary applications, so another account on
/// the same Mac must not be able to page through it.
public actor RewriteHistoryStore {

    /// Willow's own history sits around 440 rows in the reference screenshot; 500 is
    /// enough to look complete and small enough to load in one read.
    public static let capacity = 500

    private let fileURL: URL
    private var payload: Payload?

    private struct Payload: Codable {
        var enabled: Bool
        var entries: [RewriteHistoryEntry]
    }

    public init(directory: URL = RewriteHistoryStore.defaultDirectory()) {
        self.fileURL = directory.appendingPathComponent("history.json")
    }

    /// `Bundle.main.bundleIdentifier` is nil under the test runner, and §11 fixes the
    /// id anyway, so it is written out rather than looked up.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("com.core7.keigobutton.mac", isDirectory: true)
    }

    // MARK: - Reads

    public var isEnabled: Bool {
        load().enabled
    }

    /// Newest first — the order the ホーム list renders.
    public func entries() -> [RewriteHistoryEntry] {
        load().entries
    }

    public func stats(now: Date = Date()) -> RewriteStats {
        RewriteStats.from(entries: load().entries, now: now)
    }

    // MARK: - Writes

    public func setEnabled(_ enabled: Bool) {
        var current = load()
        guard current.enabled != enabled else { return }
        current.enabled = enabled
        save(current)
    }

    /// - Returns: the id to hand back to `markAccepted` later, or nil when history is
    ///   off. A nil return is the caller's signal that there is nothing to mark.
    @discardableResult
    public func record(_ entry: RewriteHistoryEntry) -> UUID? {
        var current = load()
        guard current.enabled else { return nil }
        current.entries.insert(entry, at: 0)
        if current.entries.count > Self.capacity {
            current.entries.removeLast(current.entries.count - Self.capacity)
        }
        save(current)
        return entry.id
    }

    /// The insert happens well after the record, and only sometimes — §5's write path
    /// can fail and leave the rewrite on the clipboard instead.
    public func markAccepted(id: UUID) {
        var current = load()
        guard let index = current.entries.firstIndex(where: { $0.id == id }) else { return }
        current.entries[index].accepted = true
        save(current)
    }

    public func clear() {
        var current = load()
        current.entries = []
        save(current)
    }

    // MARK: - Disk

    private func load() -> Payload {
        if let payload { return payload }
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? Self.decoder.decode(Payload.self, from: $0) }
            ?? Payload(enabled: true, entries: [])
        payload = loaded
        return loaded
    }

    /// A failed write loses the last entry, never the file — the in-memory copy stays
    /// authoritative for the session either way, so there is nothing useful to do with
    /// the error beyond not crashing over a history list.
    private func save(_ next: Payload) {
        payload = next
        guard let data = try? Self.encoder.encode(next) else { return }

        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? data.write(to: fileURL, options: .atomic)
        // `.atomic` writes through a temp file, so the mode has to be set afterwards
        // or it inherits the default umask.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
