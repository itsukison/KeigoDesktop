import DesktopRewriteKit
import Foundation

struct ConversationNodeSample {
    let role: String
    let text: String?
    let frame: CGRect?
    var isEditable: Bool? = nil
    var isSearch = false
    var sourceAttribute: String? = nil
    var failedAttributes: [String] = []
    var selected: Bool? = nil
    var expanded: Bool? = nil
    var axErrorCodes: [Int] = []
}

protocol ConversationTreeAccess {
    associatedtype Node: Hashable
    func sample(_ node: Node) -> ConversationNodeSample?
    func metadata(_ node: Node) -> ConversationNodeSample?
    func composer(_ node: Node) -> ConversationNodeSample?
    func children(_ node: Node, offset: Int, limit: Int) -> (nodes: [Node], truncated: Bool, errorCode: Int?)
}

extension ConversationTreeAccess {
    func metadata(_ node: Node) -> ConversationNodeSample? { sample(node) }
    func composer(_ node: Node) -> ConversationNodeSample? { nil }
}

public struct ReplyNodeObservation: Codable, Sendable {
    public let id: String
    public let parentId: String?
    public let role: String
    public let bounds: CGRect?
    public let sourceAttribute: String?
    public let failedAttributes: [String]
    public let clipped: Bool
    /// Local export only: explains why a discovered text candidate was retained or omitted.
    public var textDisposition: String? = nil
}

private struct ConversationWork<Node> {
    let node: Node
    let clipping: CGRect?
    let group: String
    let parent: String?
    var offset: Int? = nil
    var lane = 0
    var splitsPanes = false
    var priority = 0
}

struct ConversationTraversal {
    struct Limits {
        var nodes = 500
        var children = 200
        var blocks = 60
        var textUnits = 12000
        var seconds: TimeInterval = 1
    }
    static func read<Tree: ConversationTreeAccess>(
        tree: Tree, root: Tree.Node, excluded: Tree.Node?, snapshotId: String,
        focusPath: [Tree.Node] = [], ancestryTermination: String? = nil, limits: Limits = Limits(), now: () -> Date = Date.init,
        cancelled: () -> Bool = { Task.isCancelled }
    ) throws -> (CapturedReplyEvidence, [ReplyNodeObservation]) {
        let started = now(), deadline = started.addingTimeInterval(limits.seconds)
        // Full paths start at the retained window; partial paths must reconnect below.
        let verifiedPath = focusPath.first == root ? focusPath : []
        let focusSet = Set(focusPath)
        let safePath = Set(focusPath).count == focusPath.count ? focusPath : []
        let nextFocus = Dictionary(zip(safePath, safePath.dropFirst()), uniquingKeysWith: { first, _ in first })
        var stack = [ConversationWork(node: root, clipping: nil, group: "c0", parent: nil)]
        var visited = Set<Tree.Node>()
        var pagedChildren: [Tree.Node: Set<Tree.Node>] = [:]
        var observations: [ReplyNodeObservation] = []
        var metadata: [ReplyCaptureObservation] = []
        var blocks: [ReplySourceBlock] = []
        var regions: [ReplyCaptureRegion] = []
        var diagnostics = ReplyCaptureDiagnostics()
        diagnostics.clippedTextNodes = 0
        diagnostics.textReads = 0
        diagnostics.focusPathLength = focusPath.count
        diagnostics.focusReachesRoot = !verifiedPath.isEmpty
        var windowOrigin: CGPoint?
        var reasons = Set<String>()
        if let ancestryTermination, ancestryTermination != "root" { reasons.insert("ancestry_" + ancestryTermination) }
        var focusConnected = false
        var units = 0, workCount = 0, controlBlocks = 0, controlUnits = 0
        var composerCount = 0, structureCount = 0
        var textCandidates: [(node: Tree.Node, sample: ConversationNodeSample, visibleFrame: CGRect?, group: String, observation: Int, priority: Int, sequence: Int)] = []
        let discoveryDeadline = started.addingTimeInterval(limits.seconds * 0.65)
        var activeLane = 0, nextLane = 1, quantum = 0
        var lastServed: [Int: Int] = [:]
        func bounds(_ frame: CGRect?) -> [Double]? {
            frame.map { [Double(($0.minX - (windowOrigin?.x ?? 0)).rounded()), Double(($0.minY - (windowOrigin?.y ?? 0)).rounded()), Double(max(1, $0.width.rounded())), Double(max(1, $0.height.rounded()))] }
        }
        while !stack.isEmpty {
            if cancelled() { throw CancellationError() }
            guard now() < discoveryDeadline else { reasons.insert("time_budget"); break }
            guard visited.count < limits.nodes else { reasons.insert("node_budget"); break }
            diagnostics.pendingPeak = max(diagnostics.pendingPeak, stack.count)
            // Give each window/web split a bounded quantum; pending siblings do not
            // spend the sampling budget and a deep first pane cannot monopolize it.
            let priority = stack.map(\.priority).max() ?? 0
            let lanes = Set(stack.filter { $0.priority == priority }.map(\.lane))
            if quantum >= 64 || !lanes.contains(activeLane) {
                let alternatives = lanes.subtracting([activeLane])
                activeLane = (alternatives.isEmpty ? lanes : alternatives).min {
                    (lastServed[$0] ?? -1, $0) < (lastServed[$1] ?? -1, $1)
                } ?? activeLane
                quantum = 0
            }
            workCount += 1; quantum += 1; lastServed[activeLane] = workCount
            let entry = stack.remove(at: stack.lastIndex { $0.lane == activeLane && $0.priority == priority }!)
            if let offset = entry.offset {
                guard diagnostics.childPages < limits.nodes * 2 else { reasons.insert("child_page_budget"); continue }
                diagnostics.childPages += 1
                let page = tree.children(entry.node, offset: offset, limit: limits.children)
                if let code = page.errorCode {
                    diagnostics.childFailures += 1
                    diagnostics.axErrorCodes.append(code)
                    reasons.insert("children_unreadable")
                }
                let seen = pagedChildren[entry.node] ?? []
                let nodes = page.nodes.filter { !seen.contains($0) }
                pagedChildren[entry.node, default: []].formUnion(page.nodes)
                if !page.nodes.isEmpty && nodes.isEmpty { reasons.insert("repeated_child_page"); continue }
                if page.truncated && !page.nodes.isEmpty {
                    var continuation = entry; continuation.offset = offset + page.nodes.count
                    stack.append(continuation)
                }
                let remainingPending = max(0, limits.nodes * 4 - stack.count)
                if nodes.count > remainingPending { reasons.insert("pending_budget") }
                let childWork = nodes.prefix(remainingPending).map { node in
                    var lane = entry.lane
                    if entry.splitsPanes && nodes.count > 1 && !focusSet.contains(node) {
                        lane = nextLane; nextLane += 1
                    }
                    return ConversationWork(node: node, clipping: entry.clipping, group: entry.group, parent: entry.parent, lane: lane, priority: entry.priority)
                }
                stack.append(contentsOf: childWork.reversed())
                continue
            }
            guard visited.insert(entry.node).inserted else { continue }
            diagnostics.sampledNodes += 1
            // A partial chain becomes usable only when its top is reached through
            // ordinary traversal of the retained window. No foreign root is injected.
            if entry.node == safePath.first { focusConnected = true }
            if focusSet.contains(entry.node) { diagnostics.focusPathRead += 1 }
            let id = "n\(visited.count)"
            // The retained destination is metadata only; do not even request its value.
            if entry.node == excluded {
                if composerCount < 8 {
                    composerCount += 1
                    guard let anchor = tree.composer(entry.node) else {
                        reasons.insert("focused_anchor_unreadable")
                        diagnostics.attributeFailures += 1
                        continue
                    }
                    diagnostics.attributeFailures += anchor.failedAttributes.count
                    diagnostics.axErrorCodes += anchor.axErrorCodes
                    guard anchor.role != "AXSecureTextField" else { continue }
                    metadata.append(ReplyCaptureObservation(regionId: entry.group, role: anchor.isSearch ? "AXSearchField" : anchor.role,
                        kind: anchor.role == "AXTextArea" && !anchor.isSearch ? "composer" : "structure",
                        bounds: bounds(anchor.frame), containsFocus: focusSet.contains(entry.node)))
                } else { reasons.insert("metadata_budget") }
                continue
            }
            guard let sample = tree.metadata(entry.node) else { diagnostics.attributeFailures += 1; reasons.insert("attribute_read_failed"); continue }
            diagnostics.attributeFailures += sample.failedAttributes.count
            diagnostics.axErrorCodes += sample.axErrorCodes
            if ["AXSecureTextField", "AXMenuBar", "AXToolbar", "AXMenu"].contains(sample.role) { continue }
            let textRole = ["AXStaticText", "AXHeading", "AXTextArea", "AXButton", "AXLink", "AXPopUpButton", "AXMenuButton"].contains(sample.role)
            let visible = sample.frame.map { frame in entry.clipping.map { $0.intersection(frame) } ?? frame }
            let clipped = visible.map { $0.isNull || $0.isEmpty || (textRole && ($0.height < 6 || $0.width < 4)) } ?? false
            observations.append(ReplyNodeObservation(id: id, parentId: entry.parent, role: sample.role,
                bounds: sample.frame, sourceAttribute: sample.sourceAttribute, failedAttributes: sample.failedAttributes, clipped: clipped))
            // A collapsed wrapper can still contain readable descendants in Chromium.
            // Only omit its own text; do not infer descendant visibility from a group.
            if clipped && textRole { diagnostics.clippedTextNodes = (diagnostics.clippedTextNodes ?? 0) + 1 }
            if sample.frame == nil { reasons.insert("unknown_geometry") }
            if !sample.failedAttributes.isEmpty { reasons.insert("partial_attributes") }
            if entry.node == root { windowOrigin = sample.frame?.origin }
            let editing = sample.isEditable == true || ["AXTextField", "AXComboBox", "AXSearchField"].contains(sample.role) || (sample.role == "AXTextArea" && sample.isEditable != false)
            if editing {
                if composerCount < 8 {
                    composerCount += 1
                    metadata.append(ReplyCaptureObservation(regionId: entry.group, role: sample.isSearch ? "AXSearchField" : sample.role, kind: sample.role == "AXTextArea" && !sample.isSearch ? "composer" : "structure", bounds: bounds(sample.frame), containsFocus: focusSet.contains(entry.node)))
                } else { reasons.insert("metadata_budget") }
                continue
            }
            var clipping = entry.clipping
            if ["AXWindow", "AXScrollArea", "AXWebArea"].contains(sample.role), let frame = sample.frame {
                clipping = clipping.map { $0.intersection(frame) } ?? frame
            }
            var group = entry.group
            if regions.isEmpty || ["AXGroup", "AXSplitGroup", "AXList", "AXOutline", "AXScrollArea", "AXWebArea"].contains(sample.role) {
                // Stage structural regions within the shared node cap, then compact
                // neutral wrappers before applying the wire-format region limit.
                if regions.count < limits.nodes {
                    group = regions.isEmpty ? "c0" : "c\(visited.count)"
                    regions.append(ReplyCaptureRegion(id: group, parentId: regions.isEmpty ? nil : entry.group,
                        role: sample.role, containsFocus: focusSet.contains(entry.node), bounds: bounds(sample.frame)))
                } else { reasons.insert("region_budget") }
            }
            let control = ["AXButton", "AXLink", "AXPopUpButton", "AXMenuButton"].contains(sample.role)
            if textRole && !clipped {
                textCandidates.append((entry.node, sample, visible, group, observations.count - 1, entry.priority, visited.count))
            }
            if (sample.selected != nil || sample.expanded != nil) && structureCount < 20 {
                structureCount += 1
                metadata.append(ReplyCaptureObservation(regionId: group, role: sample.role,
                    kind: "structure", bounds: bounds(sample.frame), containsFocus: focusSet.contains(entry.node),
                    selected: sample.selected, expanded: sample.expanded))
            }
            // Page siblings after the known next focus edge, irrespective of its index.
            if !control {
                let focusDepth = focusConnected ? safePath.firstIndex(of: entry.node) : nil
                let nearbyPriority = focusDepth.map { $0 + 1 } ?? entry.priority
                stack.append(ConversationWork(node: entry.node, clipping: clipping, group: group, parent: id, offset: 0, lane: entry.lane, splitsPanes: entry.node == root || ["AXWebArea", "AXSplitGroup"].contains(sample.role), priority: nearbyPriority))
                if focusConnected, let next = nextFocus[entry.node] {
                    stack.append(ConversationWork(node: next, clipping: clipping, group: group, parent: id, lane: entry.lane, priority: 1000))
                }
            }
        }
        if stack.contains(where: { $0.offset != nil }) { reasons.insert("child_budget") }
        let composer = metadata.first { $0.containsFocus && $0.kind == "composer" }
        func rank(_ candidate: (node: Tree.Node, sample: ConversationNodeSample, visibleFrame: CGRect?, group: String, observation: Int, priority: Int, sequence: Int)) -> (Int, Int, Double, Double, Int) {
            let rect = bounds(candidate.visibleFrame ?? candidate.sample.frame)
            let known = rect == nil ? 0 : 1
            var near = 0
            var distance = Double.greatestFiniteMagnitude
            if let c = composer?.bounds, let r = rect,
               r[0] < c[0] + c[2], r[0] + r[2] > c[0], r[1] < c[1] {
                near = 1
                distance = max(0, c[1] - r[1] - r[3])
            }
            return (candidate.priority, known + near, -distance, rect.map { $0[2] * $0[3] } ?? 0, -candidate.sequence)
        }
        textCandidates.sort { rank($0) > rank($1) }
        diagnostics.textCandidates = textCandidates.count
        var retained: [(candidate: Int, sample: ConversationNodeSample)] = []
        var emptyIndices = Set<Int>()
        var unreadDisposition = "not_read"
        func record(_ index: Int, _ disposition: String, sample: ConversationNodeSample? = nil) {
            let position = textCandidates[index].observation
            let old = observations[position]
            observations[position] = ReplyNodeObservation(id: old.id, parentId: old.parentId,
                role: old.role, bounds: old.bounds, sourceAttribute: sample?.sourceAttribute ?? old.sourceAttribute,
                failedAttributes: sample?.failedAttributes ?? old.failedAttributes, clipped: old.clipped,
                textDisposition: disposition)
        }
        for (index, candidate) in textCandidates.enumerated() {
            if cancelled() { throw CancellationError() }
            guard now() < deadline else { reasons.insert("time_budget"); unreadDisposition = "time_budget"; break }
            if retained.count >= limits.blocks { reasons.insert("block_budget"); unreadDisposition = "block_budget"; break }
            let control = ["AXButton", "AXLink", "AXPopUpButton", "AXMenuButton"].contains(candidate.sample.role)
            if control && controlBlocks >= 20 { reasons.insert("label_budget"); record(index, "label_budget"); continue }
            diagnostics.textReads = (diagnostics.textReads ?? 0) + 1
            guard let sample = tree.sample(candidate.node) else {
                diagnostics.attributeFailures += 1
                record(index, "sample_unreadable"); continue
            }
            diagnostics.attributeFailures += sample.failedAttributes.count
            diagnostics.axErrorCodes += sample.axErrorCodes
            record(index, "text_unreadable", sample: sample)
            guard sample.role == candidate.sample.role else { record(index, "role_changed", sample: sample); continue }
            guard sample.isEditable != true else { record(index, "editing_changed", sample: sample); continue }
            // Geometry may change between discovery and value read; reject stale text.
            if let before = candidate.sample.frame, let after = sample.frame, before != after {
                reasons.insert("geometry_changed"); record(index, "geometry_changed", sample: sample); continue
            }
            guard let text = sample.text else { continue }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard sample.failedAttributes.isEmpty, sample.axErrorCodes.isEmpty else { continue }
                emptyIndices.insert(index)
                record(index, "empty_text", sample: sample); continue
            }
            if control && (controlUnits + text.utf16.count > 3000 || text.utf16.count > 300) { reasons.insert("label_budget"); record(index, "label_budget", sample: sample); continue }
            guard units + text.utf16.count <= limits.textUnits else { reasons.insert("text_budget"); record(index, "text_budget", sample: sample); continue }
            if control { controlBlocks += 1; controlUnits += text.utf16.count }
            units += text.utf16.count
            retained.append((index, sample))
            record(index, "retained", sample: sample)
        }
        for index in textCandidates.indices where observations[textCandidates[index].observation].textDisposition == nil {
            record(index, unreadDisposition)
        }
        // Selection rank is not chronology. Restore observed source order for provenance.
        retained.sort { textCandidates[$0.candidate].sequence < textCandidates[$1.candidate].sequence }
        for item in retained {
            let candidate = textCandidates[item.candidate], sample = item.sample
            let blockId = "b\(blocks.count)"
            let control = ["AXButton", "AXLink", "AXPopUpButton", "AXMenuButton"].contains(sample.role)
            blocks.append(ReplySourceBlock(id: blockId, conversationId: candidate.group, text: sample.text!, order: blocks.count, role: sample.role))
            metadata.append(ReplyCaptureObservation(regionId: candidate.group, blockId: blockId, role: sample.role,
                kind: control ? "control_label" : "text", bounds: bounds(sample.frame), sourceAttribute: sample.sourceAttribute))
        }
        func nearComposer(_ candidate: (node: Tree.Node, sample: ConversationNodeSample, visibleFrame: CGRect?, group: String, observation: Int, priority: Int, sequence: Int)) -> Bool {
            guard !["AXButton", "AXLink", "AXPopUpButton", "AXMenuButton", "AXHeading"].contains(candidate.sample.role),
                  let c = composer?.bounds, let r = bounds(candidate.visibleFrame ?? candidate.sample.frame) else { return false }
            return r[0] < c[0] + c[2] && r[0] + r[2] > c[0] && r[1] < c[1] && c[1] - r[1] - r[3] < 300
        }
        let retainedIndices = Set(retained.map(\.candidate))
        // Successfully read empty layout text is accounted for, not lost history.
        // Unreadable, changed and budget-omitted nodes remain conservative failures.
        diagnostics.skippedCurrentTextNodes = textCandidates.indices.filter { nearComposer(textCandidates[$0]) && !retainedIndices.contains($0) && !emptyIndices.contains($0) }.count
        if composer?.bounds != nil && (!retained.contains { nearComposer(textCandidates[$0.candidate]) } || (diagnostics.skippedCurrentTextNodes ?? 0) > 0) {
            reasons.insert("missing_current_history")
        }
        // Remove empty group leaves and collapse single-child wrappers. Branching panes,
        // text owners and field associations remain separate regions.
        let owners = Set(blocks.map(\.conversationId) + metadata.map(\.regionId))
        var parents = Dictionary(uniqueKeysWithValues: regions.map { ($0.id, $0.parentId) })
        var removed = Set<String>()
        for region in regions.reversed() where region.parentId != nil && region.role == "AXGroup" && !owners.contains(region.id) {
            let children = regions.filter { !removed.contains($0.id) && parents[$0.id] == region.id }
            if children.count <= 1 {
                if let child = children.first { parents[child.id] = region.parentId }
                removed.insert(region.id)
            }
        }
        regions = regions.filter { !removed.contains($0.id) }.map {
            ReplyCaptureRegion(id: $0.id, parentId: parents[$0.id] ?? nil, role: $0.role, containsFocus: $0.containsFocus, bounds: $0.bounds)
        }
        // Discard overflowing branches with their evidence, never flatten them
        // into a parent that would mix independent conversations.
        if regions.count > 120 {
            reasons.insert("region_budget")
            regions = Array(regions.prefix(120))
            let retained = Set(regions.map(\.id))
            blocks.removeAll { !retained.contains($0.conversationId) }
            metadata.removeAll { !retained.contains($0.regionId) }
        }
        if let excluded, !visited.contains(excluded), !focusPath.isEmpty { reasons.insert("focused_anchor_missing") }
        reasons.insert("visible_history_only")
        diagnostics.elapsedMs = min(100000, max(0, Int(now().timeIntervalSince(started) * 1000)))
        diagnostics.axErrorCodes = Array(Set(diagnostics.axErrorCodes)).sorted().prefix(20).map { $0 }
        return (CapturedReplyEvidence(version: 3, snapshotId: snapshotId, blocks: blocks,
            status: blocks.isEmpty ? .unavailable : .partial, truncationReasons: Array(reasons.sorted().prefix(20)), regions: regions,
            observations: metadata, diagnostics: diagnostics), observations)
    }
}

/// The only direct edges accepted by traversal come from retained parent identity.
/// Scheduling bounds do not shorten the timeout of an already-running AX call.
enum ConversationAncestry {
    static func read<Node: Hashable>(
        focused: Node?, root: Node, maxDepth: Int = 64, seconds: TimeInterval = 0.25,
        now: () -> Date = Date.init, cancelled: () -> Bool = { Task.isCancelled },
        parent: (Node) -> Node?
    ) throws -> (path: [Node], termination: String) {
        let deadline = now().addingTimeInterval(seconds)
        var path: [Node] = [], seen = Set<Node>(), current = focused
        while let node = current {
            if cancelled() { throw CancellationError() }
            guard now() < deadline else { return (path.reversed(), "time_budget") }
            guard path.count < maxDepth else { return (path.reversed(), "depth_budget") }
            guard seen.insert(node).inserted else { return (path.reversed(), "cycle") }
            path.append(node)
            if node == root { return (path.reversed(), "root") }
            current = parent(node)
        }
        return (path.reversed(), focused == nil ? "no_focus" : "parent_unavailable")
    }
}
