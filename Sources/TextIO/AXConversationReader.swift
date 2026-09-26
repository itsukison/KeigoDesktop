import ApplicationServices
import DesktopRewriteKit
import Foundation

public struct ReplyCaptureAnchor: Sendable {
    public let target: TextTarget
    public let draftStatus: ReplyDraftReadStatus
    let root: AXElementHandle?
    let excludedField: AXElementHandle?
    let focusedElement: AXElementHandle?
    public let selectedSource: String?
}

public actor AXConversationReader {
    public private(set) var observations: [ReplyNodeObservation] = []
    public init() {}

    public func read(_ anchor: ReplyCaptureAnchor, snapshotId: String) throws -> CapturedReplyEvidence {
        try Task.checkCancellation()
        observations = []
        if let selected = anchor.selectedSource, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var units = 0
            let text = String(selected.prefix { character in
                units += String(character).utf16.count
                return units <= 12000
            })
            return CapturedReplyEvidence(snapshotId: snapshotId, blocks: [ReplySourceBlock(id: "b0", conversationId: "c0", text: text, order: 0)], status: .partial, truncationReasons: text == selected ? ["explicit_selection"] : ["explicit_selection", "text_budget"])
        }
        guard let root = anchor.root else {
            return CapturedReplyEvidence(snapshotId: snapshotId, blocks: [], status: .unavailable, truncationReasons: ["no_window"])
        }
        // Retained element ancestry, never a new focused-element query after taking key.
        // Bound this separately; a single AX IPC can still take its 0.5 s timeout.
        let ancestry = try ConversationAncestry.read(focused: anchor.focusedElement.map { AXNode($0.element) }, root: AXNode(root.element)) { node in
            node.element.applyMessagingTimeout()
            return node.element.elementAttribute(kAXParentAttribute).map(AXNode.init)
        }
        let result = try ConversationTraversal.read(tree: AXConversationTree(), root: AXNode(root.element),
            excluded: anchor.excludedField.map { AXNode($0.element) }, snapshotId: snapshotId,
            focusPath: ancestry.path, ancestryTermination: ancestry.termination)
        observations = result.1
        return result.0
    }
}

private struct AXNode: Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

private struct AXConversationTree: ConversationTreeAccess {
    private let attributes = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, "AXEditable", kAXSelectedAttribute, kAXExpandedAttribute, kAXSubroleAttribute]

    func sample(_ node: AXNode) -> ConversationNodeSample? { sample(node, includeText: true) }
    func metadata(_ node: AXNode) -> ConversationNodeSample? { sample(node, includeText: false) }
    func composer(_ node: AXNode) -> ConversationNodeSample? { sample(node, includeText: false) }
    private func sample(_ node: AXNode, includeText: Bool) -> ConversationNodeSample? {
        let element = node.element
        element.applyMessagingTimeout()
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &raw) == .success,
              let values = raw as? [Any], values.count == attributes.count else { return nil }
        var codes: [Int] = []
        var failed = zip(attributes, values).compactMap { name, value -> String? in
            guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError else { return nil }
            var error = AXError.success
            AXValueGetValue(value as! AXValue, .axError, &error)
            if error == .attributeUnsupported || error == .noValue { return nil }
            codes.append(Int(error.rawValue))
            return name
        }
        let role = values[0] as? String ?? ""
        let editable = values[3] as? Bool
        let isText = ["AXStaticText", "AXHeading"].contains(role) || (role == "AXTextArea" && editable == false)
        let isControl = ["AXButton", "AXLink", "AXPopUpButton", "AXMenuButton"].contains(role)
        var text: String?, source: String?
        if includeText && editable != true && (isText || isControl) {
            let names = isText ? [kAXValueAttribute, kAXTitleAttribute] : [kAXTitleAttribute, kAXDescriptionAttribute]
            let read = ConversationTextRead.read(attributes: names) { name in
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
                return (value as? String, error)
            }
            text = read.text; source = read.sourceAttribute
            failed += read.failedAttributes; codes += read.axErrorCodes
        }
        return ConversationNodeSample(role: role, text: text,
            frame: Self.rectangle(position: values[1], size: values[2]), isEditable: editable,
            isSearch: role == "AXSearchField" || (values[6] as? String) == "AXSearchField",
            sourceAttribute: source, failedAttributes: failed,
            selected: values[4] as? Bool, expanded: values[5] as? Bool, axErrorCodes: codes)
    }

    func children(_ node: AXNode, offset: Int, limit: Int) -> (nodes: [AXNode], truncated: Bool, errorCode: Int?) {
        node.element.applyMessagingTimeout()
        var count = 0
        let countResult = AXUIElementGetAttributeValueCount(node.element, kAXChildrenAttribute as CFString, &count)
        if countResult == .attributeUnsupported || countResult == .noValue { return ([], false, nil) }
        if countResult == .success && offset >= count { return ([], false, nil) }
        var raw: CFArray?
        let requested = countResult == .success ? min(limit, count - offset) : limit
        let result = AXUIElementCopyAttributeValues(node.element, kAXChildrenAttribute as CFString, offset, requested, &raw)
        if result == .attributeUnsupported || result == .noValue { return ([], false, nil) }
        guard result == .success, let children = raw as? [AXUIElement] else { return ([], false, Int(result.rawValue)) }
        return (children.map(AXNode.init), countResult == .success ? offset + children.count < count : children.count == limit, nil)
    }

    private static func rectangle(position: Any, size: Any) -> CGRect? {
        guard CFGetTypeID(position as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(size as CFTypeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0, [point.x, point.y, dimensions.width, dimensions.height].allSatisfy({ $0.isFinite && abs($0) <= 100000 }) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}

/// Preserve a successful empty string separately from an unavailable value. A fallback
/// title may still supply text, but failed reads cannot certify that a node is empty.
struct ConversationTextRead {
    var text: String?
    var sourceAttribute: String?
    var failedAttributes: [String] = []
    var axErrorCodes: [Int] = []

    static func read(attributes: [String], value: (String) -> (String?, AXError)) -> Self {
        var result = Self()
        var emptySource: String?
        for name in attributes {
            let (text, error) = value(name)
            if error == .success, let text {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.text = text; result.sourceAttribute = name
                    return result
                }
                emptySource = emptySource ?? name
            } else if error != .attributeUnsupported && error != .noValue {
                result.failedAttributes.append(name)
                if error != .success { result.axErrorCodes.append(Int(error.rawValue)) }
            }
        }
        if let emptySource, result.failedAttributes.isEmpty {
            result.text = ""; result.sourceAttribute = emptySource
        }
        return result
    }
}
