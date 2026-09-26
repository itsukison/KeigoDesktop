import Foundation

public struct OnboardingLesson: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case discovery, rewrite, custom, reply }
    public enum Action: Equatable, Sendable { case polish, custom, reply }
    public enum Completion: Equatable, Sendable { case inserted, copied }
    public enum Phase: Equatable, Sendable {
        case source, focus, restore, hover, action, discovered
        case instruction, submit, generating, result, complete(Completion)
    }
    public enum Event: Equatable, Sendable {
        case hovered, collapsed, sourceSelected, sourceCleared
        case editor(ready: Bool, empty: Bool)
        case composerOpened, guidanceChanged(nonempty: Bool)
        case generating, result, cancelled, failed, completed(Completion)
    }

    public let id: UUID
    public let kind: Kind
    public private(set) var phase: Phase
    public private(set) var discovered: Bool
    public private(set) var editorReady = false
    public private(set) var sampleEmpty = false
    public private(set) var sourceSelected = false
    public private(set) var expanded = false
    public private(set) var needsRetry = false

    public init(kind: Kind, discovered: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.discovered = discovered
        phase = kind == .discovery ? (discovered ? .discovered : .hover)
            : kind == .reply ? .source : .focus
    }

    public var expectedAction: Action? {
        switch kind {
        case .discovery: return nil
        case .rewrite: return .polish
        case .custom: return .custom
        case .reply: return .reply
        }
    }

    public func allows(_ action: Action) -> Bool {
        expectedAction == action && phase == .action && editorReady
    }

    public var isComplete: Bool {
        if case .complete = phase { return true }
        return false
    }

    public mutating func receive(_ event: Event, sessionID: UUID) {
        guard sessionID == id, !isComplete else { return }
        switch event {
        case .hovered:
            expanded = true
            discovered = true
            if kind == .discovery { phase = .discovered }
            else if isPreparing { prepare() }
        case .collapsed:
            expanded = false
            if isPreparing { prepare() }
        case .sourceSelected:
            guard kind == .reply else { return }
            sourceSelected = true
            if isPreparing { prepare() }
        case .sourceCleared:
            guard kind == .reply, isPreparing else { return }
            sourceSelected = false
            prepare()
        case .editor(let ready, let empty):
            editorReady = ready
            sampleEmpty = empty
            if isPreparing { prepare() }
        case .composerOpened:
            guard kind == .custom || kind == .reply, phase == .action else { return }
            needsRetry = false
            phase = .instruction
        case .guidanceChanged(let nonempty):
            guard phase == .instruction || phase == .submit else { return }
            phase = nonempty ? .submit : .instruction
        case .generating:
            guard phase == .action || phase == .instruction || phase == .submit || phase == .result else { return }
            needsRetry = false
            phase = .generating
        case .result:
            guard phase == .generating || phase == .result else { return }
            phase = .result
        case .cancelled:
            guard kind != .discovery else { return }
            expanded = false
            prepare()
        case .failed:
            needsRetry = true
            if phase != .result { expanded = false; prepare() }
        case .completed(let completion):
            guard phase == .result else { return }
            phase = .complete(completion)
        }
    }

    private var isPreparing: Bool {
        switch phase {
        case .source, .focus, .restore, .hover, .action: return true
        default: return false
        }
    }

    private mutating func prepare() {
        guard kind != .discovery else { return }
        if kind == .reply && !sourceSelected { phase = .source }
        else if kind != .reply && sampleEmpty { phase = .restore }
        else if !editorReady { phase = .focus }
        else { phase = expanded ? .action : .hover }
    }
}
