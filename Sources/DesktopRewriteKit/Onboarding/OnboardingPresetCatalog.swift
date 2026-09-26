import Foundation

public struct OnboardingButtonDraft: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var prompt: String
    public var isEnabled: Bool?
    public var builtinKey: String?
    public var origin: PromptOrigin
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        builtinKey: String? = nil,
        isEnabled: Bool? = nil,
        origin: PromptOrigin = .onboardingPreset,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.builtinKey = builtinKey
        self.origin = origin
        self.createdAt = createdAt
    }

    public init(prompt: UserPrompt) {
        self.init(
            id: prompt.id,
            title: prompt.title,
            prompt: prompt.prompt,
            builtinKey: prompt.builtinKey,
            isEnabled: prompt.isEnabled,
            origin: prompt.origin,
            createdAt: prompt.createdAt
        )
    }

    public func userPrompt(at index: Int) -> UserPrompt {
        UserPrompt(
            id: id,
            slot: index == 0 ? .main : .sub,
            builtinKey: builtinKey,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled ?? true,
            sortOrder: index == 0 ? 0 : index - 1,
            origin: origin,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

public struct OnboardingButtonExample: Equatable, Sendable {
    public let input: String
    public let output: String
}

public enum OnboardingPresetPack: String, CaseIterable, Codable, Sendable {
    case starter
    case work
    case international
    case japanese
    case social
    case outreach
    case polish

    /// Three purpose sets, each with four buttons. Retired packs remain
    /// decodable so existing saved buttons and unfinished drafts are preserved.
    public static func available(for language: AppLanguage) -> [OnboardingPresetPack] {
        [.starter, .work, .social]
    }

    public var title: String {
        switch self {
        case .starter: return tr("毎日の文章", "Everyday", "日常写作")
        case .work: return tr("仕事の連絡", "Work messages", "工作联络")
        case .international: return tr("海外とのやり取り", "Across languages", "与海外沟通")
        case .japanese: return tr("日本語を整える", "Polish Japanese", "打磨日语")
        case .social: return tr("友達・SNS", "Friends and social", "朋友・社交")
        case .outreach: return tr("営業・依頼", "Outreach", "商务外联")
        case .polish: return tr("英語を整える", "Polish English", "打磨英语")
        }
    }

    public var caption: String {
        switch self {
        case .starter:
            return tr(
                "よく使われる4つから始める",
                "Tone, format, length and correctness",
                "从最常用的4个开始"
            )
        case .work:
            return tr(
                "社内・上司・取引先への文章を整える",
                "Chat, your manager, clients and meeting notes",
                "整理发给同事、上司和客户的文字"
            )
        case .international:
            return tr(
                "日本語と英語を場面に合わせて訳す",
                "Move between Japanese and English",
                "在日语和英语之间自然转换"
            )
        case .japanese:
            return tr(
                "誤りを直し、自然で読みやすい日本語に",
                "Fix mistakes and read naturally in Japanese",
                "改正错误，写出自然易读的日语"
            )
        case .social:
            return tr(
                "LINEやSNSで自然に伝わる文章に",
                "Sound like yourself on chat and social",
                "在LINE和社交平台上自然地表达"
            )
        case .outreach:
            return tr(
                "初回連絡・追いかけ・お断りまで",
                "First contact, follow-ups and saying no",
                "从初次联系到跟进与婉拒"
            )
        case .polish:
            return tr(
                "文法を直し、読みやすい英語に",
                "Fix grammar and read like a native writer",
                "改正语法，写出易读的英语"
            )
        }
    }

    public var buttonTitles: [String] {
        templates.map(\.title)
    }

    public func drafts() -> [OnboardingButtonDraft] {
        drafts(writtenIn: AppLanguageState.current)
    }

    /// The same buttons, for a language named explicitly rather than read off the
    /// global. `StockButtonLanguage` needs this: it builds a replacement set while
    /// reasoning about both languages at once, and a set that silently followed
    /// whichever language the app happened to be in would be the same class of bug it
    /// exists to fix.
    public func drafts(writtenIn language: AppLanguage) -> [OnboardingButtonDraft] {
        (language.writesJapanese ? japaneseTemplates : englishTemplates).map {
            OnboardingButtonDraft(
                title: $0.title,
                prompt: $0.prompt,
                builtinKey: $0.builtinKey
            )
        }
    }

    /// Every stock prompt body for one writing language, across all five packs.
    ///
    /// Takes the language as an argument instead of reading `AppLanguageState`, which
    /// is the whole point: `StockButtonLanguage` has to ask about the language the user
    /// is *not* in to notice that their buttons were authored for it. `japanese` and
    /// `simplifiedChinese` answer identically, because they write the same thing (§17).
    public static func stockPromptBodies(writtenIn language: AppLanguage) -> Set<String> {
        Set(allCases.flatMap { pack in
            (language.writesJapanese ? pack.japaneseTemplates : pack.englishTemplates)
                .map { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
        }).union(LegacyOnboardingPrompts.bodies(writtenIn: language))
    }

    /// Privacy-safe purpose key for a saved button.
    ///
    /// Exact stock bodies resolve to the explicit key on the template. An edited
    /// preset deliberately stops claiming the stock purpose, while user-authored
    /// buttons are grouped together. Titles and prompt bodies never leave the app.
    public static func buttonAnalyticsKey(for prompt: UserPrompt) -> String {
        if prompt.origin == .onboardingBuilder || prompt.origin == .userAuthored {
            return "user_authored"
        }

        let body = prompt.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let template = allCases
            .flatMap({ $0.japaneseTemplates + $0.englishTemplates })
            .first(where: {
                $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) == body
            })
        {
            return template.analyticsKey
        }

        if let key = LegacyOnboardingPrompts.analyticsKey(for: body) { return key }

        if let builtinKey = prompt.builtinKey {
            return builtinAnalyticsKeys[builtinKey] ?? "builtin_other"
        }

        switch prompt.origin {
        case .onboardingPreset:
            return "customized_preset"
        case .builtin:
            return "builtin_other"
        case .onboardingBuilder, .userAuthored:
            // Returned above. Kept exhaustive so adding an origin remains a compiler
            // error rather than silently acquiring an analytics meaning.
            return "user_authored"
        }
    }

    /// Illustrative stock copy only; an edited instruction must not imply a generated preview.
    public static func example(for draft: OnboardingButtonDraft, writtenIn language: AppLanguage) -> OnboardingButtonExample? {
        allCases.flatMap { language.writesJapanese ? $0.japaneseTemplates : $0.englishTemplates }
            .first { $0.prompt == draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines) }?.example
    }

    /// Whether the review screen still contains the selected pack unchanged.
    /// UUIDs and timestamps are intentionally ignored; content, order and count are not.
    public func isCustomized(
        drafts: [OnboardingButtonDraft],
        writtenIn language: AppLanguage
    ) -> Bool {
        let stock = self.drafts(writtenIn: language)
        guard stock.count == drafts.count else { return true }
        return zip(stock, drafts).contains { expected, actual in
            expected.title.trimmingCharacters(in: .whitespacesAndNewlines)
                != actual.title.trimmingCharacters(in: .whitespacesAndNewlines)
                || expected.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                != actual.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                || expected.builtinKey != actual.builtinKey
        }
    }

    private static let builtinAnalyticsKeys = [
        "polite": "polite",
        "email": "email",
        "translateToEnglish": "translate_english",
        "natural": "natural_japanese",
    ]

    private struct Template {
        let analyticsKey: String
        let title: String
        let prompt: String
        let example: OnboardingButtonExample
        var builtinKey: String? = nil
    }

    /// Short titles keep the four stock actions readable in the overlay.
    private var templates: [Template] {
        AppLanguageState.current.writesJapanese ? japaneseTemplates : englishTemplates
    }

    /// Shared by 日本語 and 简体中文 — see `available(for:)`. `outreach` and `polish`
    /// are English-only, so this branch only has to resolve them, never present
    /// them; each falls back to the nearest pack that does exist here rather than
    /// inventing four Japanese buttons nobody is offered.
    private var japaneseTemplates: [Template] {
        switch self {
        case .outreach: return OnboardingPresetPack.work.japaneseTemplates
        case .polish: return OnboardingPresetPack.japanese.japaneseTemplates

        case .starter:
            return [
                Template(
                    analyticsKey: "polite",
                    title: "敬語",
                    prompt: "自然な敬語に整え、ぶっきらぼうな依頼やメモも、そのまま送れる丁寧な文章にしてください。依頼は「〜していただけますか」「〜していただけますと助かります／幸いです」など、文脈に合う表現に。期限や意図を弱めず、堅くしすぎないでください。",
                    example: OnboardingButtonExample(input: "資料見た。2ページ目の数字、金曜17時までに直して。", output: "資料を確認しました。2ページ目の数字を金曜17時までに修正していただけますと助かります。"),
                    builtinKey: "polite"
                ),
                Template(
                    analyticsKey: "email",
                    title: "メール",
                    prompt: "日本語のビジネスメールに整え、宛名、空行で区切った本文、「何卒よろしくお願いいたします。」の結び、差出人名の順にしてください。宛名と差出人名は原文で分かるものだけ使い、不明なら省略してください。既存の挨拶や署名は重複させず、件名や新しい事情は加えないでください。",
                    example: OnboardingButtonExample(input: "佐藤さんへ。資料ありがとう。社内で確認して金曜までに返事する。山田", output: "佐藤様\n\n資料をお送りいただき、ありがとうございます。\n社内で確認のうえ、金曜日までにお返事いたします。\n\n何卒よろしくお願いいたします。\n山田"),
                    builtinKey: "email"
                ),
                Template(
                    analyticsKey: "translate_english",
                    title: "英訳",
                    prompt: "仕事のやり取りで使える、自然で少し丁寧な英語に翻訳してください。直訳調や大げさな表現を避け、元の意図や確実さを保ってください。",
                    example: OnboardingButtonExample(input: "今日はちょっと難しそう。明日の午後ならいけるけど、どう？", output: "Today may be difficult, but I’m available tomorrow afternoon. Would that work for you?"),
                    builtinKey: "translateToEnglish"
                ),
                Template(
                    analyticsKey: "natural_japanese",
                    title: "自然に",
                    prompt: "意味と元の語り口を保ち、不自然な言い回しや重複を直して、読みやすい日本語にしてください。必要以上に言い換えたり、丁寧さを上げたりしないでください。",
                    example: OnboardingButtonExample(input: "この機能を使うことで、毎日の文章を書く作業の時間を減らすことができます。", output: "この機能を使うと、毎日の文章を書く時間を減らせます。"),
                    builtinKey: "natural"
                ),
            ]

        case .work:
            return [
                Template(
                    analyticsKey: "work_chat",
                    title: "社内チャット",
                    prompt: "社内チャット向けに、簡潔で感じのよい文章にしてください。",
                    example: OnboardingButtonExample(input: "確認まだの人、今日中に見てほしいです。", output: "未確認の方は、今日中に確認をお願いします！")
                ),
                Template(
                    analyticsKey: "manager_message",
                    title: "上司向け",
                    prompt: "上司に伝わる、簡潔で丁寧な文章にしてください。",
                    example: OnboardingButtonExample(input: "明日午前休みたい。午後から出ます。", output: "明日の午前中、お休みをいただけますか。午後から出勤します。")
                ),
                Template(
                    analyticsKey: "client_message",
                    title: "取引先",
                    prompt: "取引先に送れる、丁寧で分かりやすい文章にしてください。",
                    example: OnboardingButtonExample(input: "見積もり送ります。確認してください。", output: "お見積もりをお送りします。ご確認いただけますと幸いです。")
                ),
                Template(
                    analyticsKey: "meeting_recap",
                    title: "会議要約",
                    prompt: "会議メモを、決定事項と次にやることが分かるように要約してください。",
                    example: OnboardingButtonExample(input: "公開は金曜。田中さんが木曜までに文章確認。価格はまだ決まってない。", output: "決定：金曜日に公開。\n次の作業：田中さんが木曜日までに文章を確認。\n未決：価格。")
                ),
            ]

        case .international:
            return [
                Template(
                    analyticsKey: "translate_english",
                    title: "英訳",
                    prompt: "自然な英語に翻訳してください。",
                    example: OnboardingButtonExample(input: "来週の火曜の午後は空いていますか？", output: "Are you free next Tuesday afternoon?"),
                    builtinKey: "translateToEnglish"
                ),
                Template(
                    analyticsKey: "translate_japanese",
                    title: "和訳",
                    prompt: "自然な日本語に翻訳してください。",
                    example: OnboardingButtonExample(input: "Could we move the meeting to Friday?", output: "打ち合わせを金曜日に変更できますか？")
                ),
                Template(
                    analyticsKey: "business_english",
                    title: "仕事英語",
                    prompt: "仕事でそのまま使える、自然で丁寧な英語にしてください。",
                    example: OnboardingButtonExample(input: "修正版を送ります。金曜までに確認をお願いします。", output: "Here's the revised version. Could you review it by Friday?")
                ),
                Template(
                    analyticsKey: "friend_english",
                    title: "友達英語",
                    prompt: "友達に送る、自然で親しみやすい英語にしてください。",
                    example: OnboardingButtonExample(input: "明日、時間あったらコーヒー飲まない？", output: "Want to grab a coffee tomorrow if you’re free?")
                ),
            ]

        case .japanese:
            return [
                Template(
                    analyticsKey: "proofread_japanese",
                    title: "校正",
                    prompt: "日本語の誤字や文法の誤りを直してください。",
                    example: OnboardingButtonExample(input: "明日は15時からで大丈夫でしょか。", output: "明日は15時からで大丈夫でしょうか。")
                ),
                Template(
                    analyticsKey: "natural_japanese",
                    title: "自然な日本語",
                    prompt: "自然で読みやすい日本語に整えてください。",
                    example: OnboardingButtonExample(input: "この案について、あなたの考えを聞くことができたら嬉しいです。", output: "この案について、ご意見を聞かせていただけると嬉しいです。")
                ),
                Template(
                    analyticsKey: "simplify_japanese",
                    title: "やさしく",
                    prompt: "やさしく分かりやすい日本語にしてください。",
                    example: OnboardingButtonExample(input: "関係各所との調整後、対応方針を共有します。", output: "関係者と相談してから、どう対応するかをお伝えします。")
                ),
                Template(
                    analyticsKey: "polite",
                    title: "敬語",
                    prompt: "自然で丁寧な敬語にしてください。",
                    example: OnboardingButtonExample(input: "明日の会議、15時に変えて。", output: "明日の会議を15時に変更していただけますか。"),
                    builtinKey: "polite"
                ),
            ]

        case .social:
            return [
                Template(
                    analyticsKey: "line_message",
                    title: "LINE",
                    prompt: "LINEで送る、短く自然なメッセージにしてください。",
                    example: OnboardingButtonExample(input: "明日の予定ですが、15時にお会いする形でよろしいでしょうか。", output: "明日15時に会うので大丈夫？")
                ),
                Template(
                    analyticsKey: "friend_message",
                    title: "友達",
                    prompt: "友達に話すような、自然で親しみやすい文章にしてください。",
                    example: OnboardingButtonExample(input: "本日はお時間をいただきありがとうございました。またお会いしましょう。", output: "今日はありがとう！また会おうね。")
                ),
                Template(
                    analyticsKey: "social_post",
                    title: "SNS投稿",
                    prompt: "SNSの投稿として、読みやすく伝わる文章にしてください。",
                    example: OnboardingButtonExample(input: "新機能できました。文章選んで押すと整います。試してね。", output: "新機能を公開しました！\n文章を選んで、ボタンを押すだけで整えられます。ぜひ試してみてください。")
                ),
                Template(
                    analyticsKey: "social_comment",
                    title: "コメント",
                    prompt: "SNSで気軽に送れる、感じのよいコメントにしてください。",
                    example: OnboardingButtonExample(input: "この写真いい。どこで撮った？", output: "素敵な写真ですね！どちらで撮られたんですか？")
                ),
            ]
        }
    }

    /// English, and not a translation of the Japanese set.
    ///
    /// 敬語 has no English counterpart — the register a Japanese user needs a button
    /// for is grammatical, and the English equivalent problem is tone, length and
    /// correctness. So the four axes replace the four honorific levels: how it
    /// sounds (Polite), what shape it takes (Email), how long it is (Shorten), and
    /// whether it is right (Proofread). `polite` and `email` keep their
    /// `builtin_key`s so the rows `handle_new_user()` already seeded are *reused*
    /// rather than left behind as Japanese buttons (§6, `UserPromptIdentity`).
    private var englishTemplates: [Template] {
        switch self {
        case .starter:
            return [
                Template(
                    analyticsKey: "polite",
                    title: "Polite",
                    prompt: "Turn rough notes, shorthand or blunt wording into a complete, natural and courteous message ready to send. Rephrase freely where needed for clarity, while keeping the intended request, facts and deadlines. Use everyday language without adding apologies, excuses or extra deference.",
                    example: OnboardingButtonExample(input: "revised file pls today by 5 need for meeting tmr", output: "Could you send the revised file by 5 today? I need it for tomorrow’s meeting."),
                    builtinKey: "polite"
                ),
                Template(
                    analyticsKey: "email",
                    title: "Email",
                    prompt: "Turn the text into an approachable professional email with a greeting, readable paragraphs separated by blank lines, and a closing such as “Best,” followed by the sender’s name. Use recipient and sender names only when supplied; omit unknown names. Keep existing greetings and signatures without duplication, and do not add a subject or new facts.",
                    example: OnboardingButtonExample(input: "To Sam. thanks for the proposal. ill review it with the team and reply by friday. Alex", output: "Hi Sam,\n\nThanks for sending the proposal. I’ll review it with the team and get back to you by Friday.\n\nBest,\nAlex"),
                    builtinKey: "email"
                ),
                Template(
                    analyticsKey: "shorten",
                    title: "Shorten",
                    prompt: "Remove filler and repetition to make the text shorter. Keep every distinct point, question, request and deadline, and preserve the writer’s tone; do not turn it into a summary.",
                    example: OnboardingButtonExample(input: "I just wanted to check whether you’ve had a chance to review the proposal I sent on Monday. We need your feedback by Thursday so we can finalize the budget on Friday.", output: "Have you reviewed the proposal I sent Monday? We need your feedback by Thursday to finalize the budget Friday.")
                ),
                Template(
                    analyticsKey: "proofread_english",
                    title: "Proofread",
                    prompt: "Correct spelling, grammar and punctuation. Keep the writer’s wording, tone and structure wherever they are already correct, without polishing or rephrasing for style.",
                    example: OnboardingButtonExample(input: "Me and Sam was going to send the report yesterday, but we didn’t had the final numbers.", output: "Sam and I were going to send the report yesterday, but we didn’t have the final numbers.")
                ),
            ]

        case .work:
            return [
                Template(
                    analyticsKey: "work_chat",
                    title: "Chat",
                    prompt: "Make this clear and friendly for a work chat.",
                    example: OnboardingButtonExample(input: "review still missing. need it today.", output: "Could someone finish the review today? Thanks!")
                ),
                Template(
                    analyticsKey: "manager_message",
                    title: "Manager",
                    prompt: "Make this clear and respectful for my manager.",
                    example: OnboardingButtonExample(input: "need tomorrow morning off. back after lunch.", output: "Could I take tomorrow morning off? I’ll be back after lunch.")
                ),
                Template(
                    analyticsKey: "client_message",
                    title: "Client",
                    prompt: "Make this clear and professional for a client.",
                    example: OnboardingButtonExample(input: "sending the estimate. have a look.", output: "Here’s the estimate for your review.")
                ),
                Template(
                    analyticsKey: "meeting_recap",
                    title: "Recap",
                    prompt: "Summarize these notes into decisions and next steps.",
                    example: OnboardingButtonExample(input: "launch friday. sam checks copy thursday. price undecided.", output: "Decision: Launch Friday.\nNext step: Sam reviews the copy Thursday.\nOpen question: Pricing.")
                ),
            ]

        case .outreach:
            return [
                Template(
                    analyticsKey: "follow_up",
                    title: "Follow-up",
                    prompt: "Write a friendly follow-up.",
                    example: OnboardingButtonExample(input: "checking on the quote i sent last week.", output: "Just following up on the quote I sent last week. Have you had a chance to look it over?")
                ),
                Template(
                    analyticsKey: "first_contact",
                    title: "Intro",
                    prompt: "Turn this into a friendly introduction with a clear ask.",
                    example: OnboardingButtonExample(input: "hi, we built a writing tool. want a demo this week?", output: "Hi, we’ve built a tool to help with everyday writing. Would you be interested in a demo this week?")
                ),
                Template(
                    analyticsKey: "persuasive",
                    title: "Persuade",
                    prompt: "Make this more persuasive using the ideas already here.",
                    example: OnboardingButtonExample(input: "use the template. it saves setup time.", output: "Save time on setup by starting with the template.")
                ),
                Template(
                    analyticsKey: "decline",
                    title: "Decline",
                    prompt: "Help me say no politely and clearly.",
                    example: OnboardingButtonExample(input: "cant take this on. my quarter is full.", output: "Thanks for thinking of me. I’m fully booked this quarter, so I’ll have to pass.")
                ),
            ]

        case .polish:
            return [
                Template(
                    analyticsKey: "grammar",
                    title: "Grammar",
                    prompt: "Fix the grammar and spelling.",
                    example: OnboardingButtonExample(input: "We has finish the report yesterday.", output: "We finished the report yesterday.")
                ),
                Template(
                    analyticsKey: "natural_english",
                    title: "Natural",
                    prompt: "Make this sound natural in English.",
                    example: OnboardingButtonExample(input: "Please let me know your convenient time.", output: "Please let me know what time works for you.")
                ),
                Template(
                    analyticsKey: "simplify_english",
                    title: "Simplify",
                    prompt: "Make this easy to understand in plain English.",
                    example: OnboardingButtonExample(input: "We will commence implementation following stakeholder alignment.", output: "We’ll start once everyone involved agrees.")
                ),
                Template(
                    analyticsKey: "formal_english",
                    title: "Formal",
                    prompt: "Rewrite this in a formal, professional tone.",
                    example: OnboardingButtonExample(input: "we cant finish friday. moving it to monday.", output: "We are unable to complete this by Friday. Completion has been moved to Monday.")
                ),
            ]

        case .social:
            return [
                Template(
                    analyticsKey: "friendly_chat",
                    title: "Friendly",
                    prompt: "Make this warm and conversational.",
                    example: OnboardingButtonExample(input: "I would appreciate an update when you have availability.", output: "Could you give me an update when you get a chance?")
                ),
                Template(
                    analyticsKey: "social_post",
                    title: "Post",
                    prompt: "Turn this into an engaging, readable social post.",
                    example: OnboardingButtonExample(input: "new feature today. select text press button. give it a go.", output: "New today: select your text, press a button, and give your writing a polish. Try it out!")
                ),
                Template(
                    analyticsKey: "social_comment",
                    title: "Comment",
                    prompt: "Make this a friendly, thoughtful public comment.",
                    example: OnboardingButtonExample(input: "good explanation. the example helped.", output: "Great explanation! The example really helped it click.")
                ),
                Template(
                    analyticsKey: "casual_message",
                    title: "Casual",
                    prompt: "Make this relaxed and natural for a friend.",
                    example: OnboardingButtonExample(input: "I regret to inform you that I will arrive fifteen minutes late.", output: "Sorry, I’m running 15 minutes late!")
                ),
            ]

        // Offered only when the buttons write Japanese (`available(for:)`); present
        // here so a pack saved before a language change still resolves.
        case .international: return OnboardingPresetPack.polish.englishTemplates
        case .japanese: return OnboardingPresetPack.polish.englishTemplates
        }
    }
}

public enum OnboardingPracticeSample {
    public static func text(for prompt: UserPrompt) -> String {
        let clue = "\(prompt.title) \(prompt.prompt)".lowercased()

        if !AppLanguageState.current.writesJapanese {
            return englishText(clue: clue, builtinKey: prompt.builtinKey)
        }

        if prompt.builtinKey == "translateToEnglish"
            || clue.contains("英訳") || clue.contains("英語")
        {
            return "来週の打ち合わせを火曜日の午後に変更できますか？"
        }
        if clue.contains("和訳") || clue.contains("日本語に翻訳") {
            return "Could we move next week's meeting to Tuesday afternoon?"
        }
        if clue.contains("会議要約") || clue.contains("決定事項") || clue.contains("要約") {
            return "定例会議メモ\n新しい案内ページは金曜公開。田中さんが文章、佐藤さんが画像を木曜までに確認。価格は来週決める。"
        }
        if clue.contains("校正") || clue.contains("誤字") || clue.contains("脱字") {
            return "明日の打ち合わせは、15時からで大丈夫でしょか。資料も確認お願い致します。"
        }
        if clue.contains("やさしく") || clue.contains("分かりやす") {
            return "本件については関係各所との調整を実施した上で、可及的速やかに対応方針を共有いたします。"
        }
        if clue.contains("line") || clue.contains("友達") || clue.contains("親しみ") {
            return "明日の予定ですが、もしよろしければ15時からお会いする形でも問題ないでしょうか。"
        }
        if clue.contains("sns") || clue.contains("投稿") || clue.contains("コメント") {
            return "新しい機能を公開しました 文章を選んでボタンを押すだけ ぜひ使ってみてください"
        }
        if clue.contains("社内チャット") || clue.contains("slack") || clue.contains("teams") {
            return "来週のリリース、確認がまだのところがあります。今日中に見てもらえると助かります。"
        }
        if clue.contains("上司") {
            return "明日の会議を15時に変えたいです。予定は大丈夫ですか。"
        }
        if clue.contains("取引先") || clue.contains("ビジネスメール") || clue.contains("メール") {
            return "明日の打ち合わせを15時に変更したいです。ご都合を確認したいです。"
        }
        if prompt.builtinKey == "polite" || clue.contains("敬語") || clue.contains("丁寧") {
            return "明日の会議、15時に変更しといて"
        }
        if prompt.builtinKey == "natural" || clue.contains("自然") {
            return "明日のミーティングは15時へチェンジすることは可能でしょうか。"
        }

        return "来週の打ち合わせについて、火曜か水曜の午後で都合のよい時間を教えてください。"
    }

    /// The English practice draft has to be *wrong* in the way its button fixes,
    /// or the lesson ends with a rewrite that looks identical to the input. Each
    /// sample carries the specific defect: blunt for Polite, padded for Shorten,
    /// misspelled for Proofread, translated-sounding for Natural.
    private static func englishText(clue: String, builtinKey: String?) -> String {
        if clue.contains("recap") || clue.contains("notes") || clue.contains("decisions") {
            return "standup notes\nnew pricing page ships friday. dana writes the copy, sam checks the images by thursday. we decide the discount next week."
        }
        if clue.contains("proofread") || clue.contains("spelling") || clue.contains("grammar") {
            return "Just wanted to confirm that tommorow meeting is still at 3pm, and if you could sent me the deck before then that would be great."
        }
        if clue.contains("shorten") || clue.contains("fewer words") || clue.contains("concise") {
            return "I just wanted to quickly reach out and check in with you about whether or not it might potentially be possible for us to move the meeting that we have scheduled for tomorrow afternoon to a slightly later time, if that works for you."
        }
        if clue.contains("simplify") || clue.contains("plain english") {
            return "Following alignment with the relevant stakeholders, we will endeavour to disseminate the finalised remediation approach at the earliest available juncture."
        }
        if clue.contains("follow-up") || clue.contains("follow up") || clue.contains("not been answered") {
            return "hi, checking in again on the quote I sent last week. let me know."
        }
        if clue.contains("decline") || clue.contains("say no") {
            return "cant take this on right now, my quarter is full. maybe later"
        }
        if clue.contains("intro") || clue.contains("first-contact") || clue.contains("persuade") {
            return "hi, we built a tool that fixes your writing. it saves time. want a demo this week?"
        }
        if clue.contains("chat") || clue.contains("slack") || clue.contains("teams") {
            return "hey there are still a few things not reviewed for next weeks release, would be great if someone could look today"
        }
        if clue.contains("manager") {
            return "want to move tomorrows meeting to 3. does that work"
        }
        if clue.contains("client") || clue.contains("email") || builtinKey == "email" {
            return "need to move tomorrows meeting to 3pm. checking if thats ok with you"
        }
        if clue.contains("post") || clue.contains("comment") || clue.contains("social") {
            return "we shipped a new thing today you select some text and press a button thats it please try it"
        }
        if clue.contains("casual") || clue.contains("friendly") || clue.contains("friend") {
            return "I am writing to inform you that I will unfortunately be arriving approximately fifteen minutes later than the agreed time."
        }
        if clue.contains("formal") {
            return "so we cant get it done by friday, well push it to monday instead. hope thats fine"
        }
        if clue.contains("natural") {
            return "I think that it is possible to change tomorrow's meeting into 3 o'clock, if your convenience is good."
        }
        if builtinKey == "polite" || clue.contains("polite") || clue.contains("courteous") {
            return "move tomorrows meeting to 3, i cant make the morning"
        }

        return "let me know what time works for you tuesday or wednesday afternoon for next weeks meeting"
    }
}
