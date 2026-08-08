import Darwin
import Foundation

/// pid → bundle identifier, without AppKit.
///
/// `NSRunningApplication` would be the obvious answer, but §3 keeps AppKit out of
/// `Sources/` so this layer stays testable without a window server. `proc_pidpath`
/// plus the bundle's own Info.plist gets there with Darwin and Foundation only.
enum BundleIdentity {

    private static let cache = Cache()

    static func bundleIdentifier(for pid: pid_t) -> String? {
        if let hit = cache.value(for: pid) { return hit }
        guard let identifier = lookUp(pid: pid) else { return nil }
        cache.store(identifier, for: pid)
        return identifier
    }

    private static func lookUp(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let written = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard written > 0 else { return nil }

        let executable = URL(fileURLWithPath: String(cString: buffer))

        // .../Foo.app/Contents/MacOS/Foo → .../Foo.app. Walk up rather than
        // assuming a fixed depth: some bundles nest helpers deeper.
        var candidate = executable
        while candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
            guard candidate.pathExtension == "app" else { continue }
            let plist = candidate
                .appendingPathComponent("Contents")
                .appendingPathComponent("Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let root = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil
                  ) as? [String: Any],
                  let identifier = root["CFBundleIdentifier"] as? String
            else { return nil }
            return identifier
        }
        return nil
    }

    /// Bundle ids never change for a live pid, and pids are reused rarely enough
    /// that a stale entry costs an analytics label, not a correctness bug.
    private final class Cache: @unchecked Sendable {
        private var storage: [pid_t: String] = [:]
        private let lock = NSLock()

        func value(for pid: pid_t) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return storage[pid]
        }

        func store(_ value: String, for pid: pid_t) {
            lock.lock()
            defer { lock.unlock() }
            storage[pid] = value
        }
    }
}
