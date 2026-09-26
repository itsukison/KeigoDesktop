import Foundation

public enum WritingSurfaceHint: String, Codable, Sendable { case prose, mail, chat, excluded, unknown }

public struct WritingSurfaceEvidence: Sendable {
    public let bundleID: String?
    public let url: String?
    public let hint: WritingSurfaceHint
    public init(bundleID: String?, url: String?, hint: WritingSurfaceHint) {
        self.bundleID = bundleID; self.url = url; self.hint = hint
    }
}

public enum WritingContextResolver {
    public struct Resolution: Equatable, Sendable {
        public let context: WritingContext
        public let source: WritingContextSource
    }
    public static func mappingKey(bundleID: String?, browserURL: String?) -> String? {
        if let url = browserURL.flatMap(URL.init(string:)),
           ["https", "http"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased() {
            return "site:" + host
        }
        guard let bundleID, !isBrowser(bundleID) else { return nil }
        return "app:" + bundleID
    }
    public static func resolve(bundleID: String?, browserURL: String?,
                               override: WritingContext? = nil,
                               mappings: [String: WritingContext] = [:],
                               excluded: Bool = false, hint: WritingSurfaceHint = .unknown) -> Resolution {
        guard !excluded, hint != .excluded else { return Resolution(context: .other, source: .unknown) }
        if let override { return Resolution(context: override, source: .userOnce) }
        if let key = mappingKey(bundleID: bundleID, browserURL: browserURL), let context = mappings[key] {
            return Resolution(context: context, source: .userMapping)
        }
        if let url = browserURL.flatMap(URL.init(string:)), let host = url.host?.lowercased(),
           ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            let path = url.path.lowercased()
            let context: WritingContext?
            if host == "mail.google.com", hint != .chat, !(url.fragment?.hasPrefix("chat/") ?? false) { context = .email }
            else if ["outlook.live.com", "outlook.office.com", "outlook.office365.com"].contains(host), (path == "/mail" || path.hasPrefix("/mail/")) { context = .email }
            else if host == "app.slack.com", path.hasPrefix("/client/"), !path.contains("/canvas") { context = .workChat }
            else if ["teams.microsoft.com", "teams.cloud.microsoft"].contains(host), path.hasPrefix("/v2"), url.fragment?.hasPrefix("/chat") == true { context = .workChat }
            else if host == "web.whatsapp.com" { context = .personal }
            else { context = nil }
            return Resolution(context: context ?? .other, source: context == nil ? .unknown : .knownSurface)
        }
        if let bundleID, isBrowser(bundleID), hint == .mail {
            return Resolution(context: .email, source: .knownSurface)
        }
        let context: WritingContext?
        switch bundleID {
        case "com.apple.mail": context = .email
        case "com.microsoft.Outlook" where hint == .mail: context = .email
        case "com.tinyspeck.slackmacgap" where hint == .chat: context = .workChat
        case "com.microsoft.teams2" where hint == .chat: context = .workChat
        case "com.microsoft.teams" where hint == .chat: context = .workChat
        case "com.apple.MobileSMS", "jp.naver.line.mac", "net.whatsapp.WhatsApp": context = .personal
        default: context = nil
        }
        return Resolution(context: context ?? .other, source: context == nil ? .unknown : .appDefault)
    }
    public static func isBrowser(_ bundleID: String) -> Bool {
        ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "company.thebrowser.Browser", "org.mozilla.firefox", "com.brave.Browser", "com.operasoftware.Opera"].contains(bundleID)
            || bundleID.hasPrefix("com.google.Chrome.")
    }
}
