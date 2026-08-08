import Foundation
import Security

public struct AuthSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userId: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userId: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
    }
}

public protocol SessionStoring: Sendable {
    func read() -> AuthSession?
    func write(_ session: AuthSession)
    func clear()
}

/// §6: session storage is the macOS Keychain.
///
/// Not an App Group — that is the iOS container↔extension mechanism and has no role
/// on macOS. One generic-password item holding the whole session as JSON, so the
/// three tokens can never be written half-updated.
public struct KeychainSessionStore: SessionStoring {

    /// §11. Distinct from the iOS app's item so signing out on one surface does not
    /// disturb the other.
    public static let service = "com.core7.keigobutton.mac.session"
    private static let account = "supabase"

    public init() {}

    public func read() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func write(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // The app refreshes tokens on launch, before the user has necessarily
            // unlocked anything, so this cannot require an unlocked-and-passcoded
            // device the way the iOS equivalent can.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    public func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// For tests and previews.
public final class InMemorySessionStore: SessionStoring, @unchecked Sendable {
    private var session: AuthSession?
    private let lock = NSLock()

    public init(session: AuthSession? = nil) {
        self.session = session
    }

    public func read() -> AuthSession? {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    public func write(_ session: AuthSession) {
        lock.lock(); defer { lock.unlock() }
        self.session = session
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        session = nil
    }
}
