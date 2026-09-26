import Foundation
import Darwin
import DesktopRewriteKit

public struct BrowserReplyBinding: Codable, Equatable, Sendable {
    public var connectionId: String?
    public let documentToken: String
    public let conversationId: String
    public let composerId: String
    public let tabId: Int
    public let windowId: Int
    public let documentId: String
    public let frameId: Int
}

public struct BrowserReplyRequest: Codable, Sendable {
    public var `protocol` = 1
    public var id = UUID().uuidString
    public var operation: String
    public var snapshotId: String?
    public var binding: BrowserReplyBinding?
    public var requireFocus: Bool = false
    public var expectedText: String?
}
public struct BrowserReplyResponse: Codable, Sendable {
    public let `protocol`: Int
    public let id: String
    public let status: String
    public let reason: String?
    public let result: String?
    public var binding: BrowserReplyBinding?
    public let evidence: CapturedReplyEvidence?
}
public enum BrowserReplyError: Error, Sendable {
    case failure(String)
    public var reason: String { switch self { case .failure(let reason): return reason } }
}

/// Length-framed, bounded local transport shared by the app and native messaging host.
/// Blocking I/O runs only on dedicated queues, never the main actor.
public enum ReplyBridgeWire {
    public static let limit = 256_000
    public static let host = "com.core7.keigobutton.reply"
    public static var directory: URL {
        #if DEBUG
        if let raw = getenv("KEIGO_REPLY_BRIDGE_DIR") { return URL(fileURLWithPath: String(cString: raw)) }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/KeigoButton/ReplyBridge")
    }
    public static var path: String { directory.appendingPathComponent("bridge.sock").path }
    public static func frame(_ body: Data) throws -> Data {
        guard body.count <= limit else { throw BrowserReplyError.failure("payload_too_large") }
        var size = UInt32(body.count).littleEndian
        var data = withUnsafeBytes(of: &size) { Data($0) }; data.append(body); return data
    }
    public static func readFrame(_ fd: Int32, deadline: Date? = nil) throws -> Data {
        func readExactly(_ count: Int) throws -> Data {
            var data = Data(count: count), offset = 0
            try data.withUnsafeMutableBytes { bytes in
                while offset < count {
                    if let deadline {
                        let remaining = deadline.timeIntervalSinceNow
                        guard remaining > 0 else { throw BrowserReplyError.failure("transport_unavailable") }
                        var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                        let ready = poll(&p, 1, Int32(min(remaining * 1000, 3000)))
                        if ready < 0 && errno == EINTR { continue }
                        guard ready > 0 else { throw BrowserReplyError.failure("transport_unavailable") }
                    }
                    let n = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset)
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw BrowserReplyError.failure("transport_unavailable") }
                    offset += n
                }
            }
            return data
        }
        let header = try readExactly(4)
        let count = header.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        guard count > 0 && count <= limit else { throw BrowserReplyError.failure("payload_too_large") }
        return try readExactly(count)
    }
    public static func writeFrame(_ body: Data, to fd: Int32) throws {
        let data = try frame(body)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < data.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), data.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw BrowserReplyError.failure("transport_unavailable") }
                offset += n
            }
        }
    }
    static func address<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw BrowserReplyError.failure("socket_path") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in raw.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return try withUnsafePointer(to: &addr) { ptr in
            try ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
    static func configure(_ fd: Int32) {
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
    }
    static func deadline(_ fd: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }
    public static func connectSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrowserReplyError.failure("transport_unavailable") }
        configure(fd)
        let result = try address { Darwin.connect(fd, $0, $1) }
        guard result == 0 else { close(fd); throw BrowserReplyError.failure("transport_unavailable") }
        return fd
    }
}

private struct BridgeHello: Codable {
    let version: Int
    let origin: String
    let browserPID: Int32
}

/// Chrome owns stdin/stdout; this process relays only protocol frames to the local app.
public enum ReplyNativeHost {
    public static func run(origin: String) throws {
        guard origin == ReplyBridgeIdentity.origin else { throw BrowserReplyError.failure("origin_mismatch") }
        let fd = try ReplyBridgeWire.connectSocket()
        defer { close(fd) }
        let hello = BridgeHello(version: 1, origin: origin, browserPID: getppid())
        try ReplyBridgeWire.writeFrame(JSONEncoder().encode(hello), to: fd)
        DispatchQueue.global().async {
            do { while true { try ReplyBridgeWire.writeFrame(ReplyBridgeWire.readFrame(STDIN_FILENO), to: fd) } }
            catch { shutdown(fd, SHUT_RDWR) }
        }
        while true { try ReplyBridgeWire.writeFrame(ReplyBridgeWire.readFrame(fd), to: STDOUT_FILENO) }
    }
}

private final class BrowserPeer: @unchecked Sendable {
    let id = UUID().uuidString
    let fd: Int32
    let browserPID: Int32
    let queue = DispatchQueue(label: "reply.browser.peer")
    init(fd: Int32, browserPID: Int32) { self.fd = fd; self.browserPID = browserPID }
    deinit { close(fd) }
    func request(_ request: BrowserReplyRequest) async throws -> BrowserReplyResponse {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    ReplyBridgeWire.deadline(self.fd, seconds: 3)
                    try ReplyBridgeWire.writeFrame(JSONEncoder().encode(request), to: self.fd)
                    let response = try JSONDecoder().decode(BrowserReplyResponse.self, from: ReplyBridgeWire.readFrame(self.fd, deadline: Date().addingTimeInterval(3)))
                    guard response.protocol == 1, response.id == request.id else { throw BrowserReplyError.failure("stale_response") }
                    continuation.resume(returning: response)
                } catch { shutdown(self.fd, SHUT_RDWR); continuation.resume(throwing: error) }
            }
        }
    }
}

public final class BrowserReplyBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var peers: [BrowserPeer] = []
    private var listener: Int32 = -1
    public private(set) var startupFailure: String?
    public init() {
        #if DEBUG
        do { try start() } catch { startupFailure = String(describing: error) }
        #endif
    }
    public func stop() {
        lock.lock(); let all = peers; peers = []; let fd = listener; listener = -1; lock.unlock()
        for peer in all { shutdown(peer.fd, SHUT_RDWR) }
        if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); unlink(ReplyBridgeWire.path) }
    }
    private func start() throws {
        try FileManager.default.createDirectory(at: ReplyBridgeWire.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(ReplyBridgeWire.directory.path, 0o700)
        // Do not steal another running app's socket.
        if let fd = try? ReplyBridgeWire.connectSocket() { close(fd); return }
        unlink(ReplyBridgeWire.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BrowserReplyError.failure("transport_unavailable") }
        ReplyBridgeWire.configure(fd)
        let bound = try ReplyBridgeWire.address { Darwin.bind(fd, $0, $1) }
        guard bound == 0 && listen(fd, 8) == 0 else { close(fd); throw BrowserReplyError.failure("transport_unavailable") }
        chmod(ReplyBridgeWire.path, 0o600); listener = fd
        DispatchQueue.global().async { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { break }
                ReplyBridgeWire.configure(client)
                DispatchQueue.global().async { [weak self] in
                    do {
                        ReplyBridgeWire.deadline(client, seconds: 3)
                        var uid: uid_t = 0, gid: gid_t = 0
                        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { throw BrowserReplyError.failure("peer_rejected") }
                        let hello = try JSONDecoder().decode(BridgeHello.self, from: ReplyBridgeWire.readFrame(client, deadline: Date().addingTimeInterval(3)))
                        guard hello.version == 1, hello.origin == ReplyBridgeIdentity.origin, let self else { throw BrowserReplyError.failure("protocol_mismatch") }
                        self.lock.lock(); self.peers.append(BrowserPeer(fd: client, browserPID: hello.browserPID)); self.lock.unlock()
                    } catch { close(client) }
                }
            }
        }
    }
    var connectedBrowserPIDs: [Int32] { connections().map(\.browserPID) }
    private func connections() -> [BrowserPeer] { lock.lock(); defer { lock.unlock() }; return peers }
    private func remove(_ id: String) { lock.lock(); defer { lock.unlock() }; peers.removeAll { $0.id == id } }
    public func capture(snapshotId: String, browserPID: Int32) async throws -> BrowserReplyResponse {
        let clients = connections().filter { $0.browserPID == browserPID }
        guard !clients.isEmpty else { throw BrowserReplyError.failure("extension_unavailable") }
        let responses = await withTaskGroup(of: (String, BrowserReplyResponse?).self) { group in
            for client in clients { group.addTask { (client.id, try? await client.request(BrowserReplyRequest(operation: "capture", snapshotId: snapshotId))) } }
            var result: [(String, BrowserReplyResponse)] = []
            for await (id, response) in group {
                if let response { result.append((id, response)) } else { self.remove(id) }
            }
            return result
        }
        try Task.checkCancellation()
        let active = responses.filter { $0.1.reason != "not_focused" }
        guard active.count <= 1 else { throw BrowserReplyError.failure("ambiguous_target") }
        guard let (id, response) = active.first else { throw BrowserReplyError.failure(responses.isEmpty ? "transport_unavailable" : "target_changed") }
        guard response.status == "ok", let evidence = response.evidence, evidence.version == 4, evidence.snapshotId == snapshotId, let dom = evidence.dom, let binding = response.binding, binding.conversationId == dom.conversationId, binding.composerId == dom.composerId else { throw BrowserReplyError.failure(response.reason ?? "invalid_dom_capture") }
        guard evidence.blocks.count <= 60, evidence.blocks.reduce(0, { $0 + $1.text.utf16.count }) <= 12000 else { throw BrowserReplyError.failure("capture_budget") }
        var result = response; result.binding?.connectionId = id; return result
    }
    public func validate(_ binding: BrowserReplyBinding, focused: Bool = false, expectedText: String? = nil) async throws -> String {
        guard let peer = connections().first(where: { $0.id == binding.connectionId }) else { throw BrowserReplyError.failure("transport_unavailable") }
        let response = try await peer.request(BrowserReplyRequest(operation: expectedText == nil ? "validate" : "verify", binding: binding, requireFocus: focused, expectedText: expectedText))
        guard response.status == "ok", let result = response.result else { throw BrowserReplyError.failure(response.reason ?? "target_changed") }
        return result
    }
}
