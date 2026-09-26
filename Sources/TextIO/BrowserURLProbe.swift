import Foundation

enum BrowserURLProbe {
    struct NodeInfo<Node> {
        let url: String?
        let parent: Node?
    }
    struct Result {
        let url: String?
        let source: String
        let depth: Int
    }

    static func httpURL(_ raw: String?) -> String? {
        guard let raw, let url = URL(string: raw),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url.absoluteString
    }

    static func resolve<Node>(from start: Node, sameNode: (Node, Node) -> Bool,
                              read: (Node) -> NodeInfo<Node>, documentURL: () -> String?,
                              now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) -> Result {
        let deadline = now() + 0.2
        var current: Node? = start
        var visited: [Node] = []
        var stop = "root"
        while let node = current {
            guard visited.count < 64 else { stop = "depth_limit"; break }
            guard now() < deadline else { stop = "time_limit"; break }
            guard !visited.contains(where: { sameNode($0, node) }) else { stop = "cycle"; break }
            visited.append(node)
            let info = read(node)
            if let url = httpURL(info.url) {
                return Result(url: url, source: "web_area", depth: visited.count)
            }
            current = info.parent
        }
        if now() < deadline, let url = httpURL(documentURL()) {
            return Result(url: url, source: "window_document", depth: visited.count)
        }
        return Result(url: nil, source: stop, depth: visited.count)
    }
}
