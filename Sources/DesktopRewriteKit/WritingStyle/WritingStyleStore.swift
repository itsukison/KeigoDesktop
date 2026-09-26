import Foundation

public struct WritingStyleDocument: Codable, Equatable, Sendable {
    public var version = 1
    public var profiles: [WritingStyleProfile] = WritingContext.allCases.map(WritingStyleProfile.init)
    public var mappings: [String: WritingContext] = [:]
    public init() {}
    public func profile(for context: WritingContext) -> WritingStyleProfile {
        profiles.first { $0.context == context } ?? WritingStyleProfile(context: context)
    }
    public mutating func set(_ profile: WritingStyleProfile) {
        profiles.removeAll { $0.context == profile.context }
        profiles.append(profile)
    }
    private enum CodingKeys: String, CodingKey { case version, profiles, mappings }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "Unsupported style version")
        }
        profiles = try c.decodeIfPresent([WritingStyleProfile].self, forKey: .profiles) ?? []
        guard Set(profiles.map(\.context)).count == profiles.count else {
            throw DecodingError.dataCorruptedError(forKey: .profiles, in: c, debugDescription: "Duplicate profile")
        }
        for context in WritingContext.allCases where !profiles.contains(where: { $0.context == context }) {
            profiles.append(WritingStyleProfile(context: context))
        }
        mappings = try c.decodeIfPresent([String: WritingContext].self, forKey: .mappings) ?? [:]
    }
}

@MainActor
public final class WritingStyleStore {
    public private(set) var document = WritingStyleDocument()
    public private(set) var accountID: String?
    public private(set) var activationRevision: UInt64 = 0
    public private(set) var error: String?
    private let directory: URL
    private var recoveryRequired = false

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KeigoButton/WritingStyle", isDirectory: true)
    }

    @discardableResult
    public func activate(accountID: String?, expectedRevision: UInt64? = nil) -> Bool {
        if let expectedRevision, expectedRevision != activationRevision { return false }
        guard self.accountID != accountID else { return true }
        activationRevision &+= 1
        self.accountID = accountID
        document = WritingStyleDocument()
        error = nil
        recoveryRequired = false
        guard let url = fileURL else { return true }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                document = try JSONDecoder().decode(WritingStyleDocument.self, from: Data(contentsOf: url))
            }
        } catch {
            recoveryRequired = true
            self.error = "load"
        }
        return true
    }

    @discardableResult
    public func save(_ document: WritingStyleDocument, for accountID: String?) -> Bool {
        guard let accountID, accountID == self.accountID, let url = fileURL else { return false }
        guard !recoveryRequired else { return false }
        self.document = document
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(document).write(to: url, options: .atomic)
            error = nil
            return true
        } catch {
            self.error = "save"
            return false
        }
    }

    @discardableResult
    public func recoverWithDefaults() -> Bool {
        guard recoveryRequired, let url = fileURL else { return false }
        do {
            let backup = url.appendingPathExtension("preserved-" + UUID().uuidString)
            try FileManager.default.copyItem(at: url, to: backup)
            recoveryRequired = false
            return save(WritingStyleDocument(), for: accountID)
        } catch {
            self.error = "load"
            return false
        }
    }

    private var fileURL: URL? {
        guard let accountID else { return nil }
        let filename = Data(accountID.utf8).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(filename + ".json")
    }
}
