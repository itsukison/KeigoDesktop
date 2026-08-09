import Foundation

public struct OnboardingButtonDraft: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var prompt: String
    public var builtinKey: String?
    public var origin: PromptOrigin
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        builtinKey: String? = nil,
        origin: PromptOrigin = .onboardingPreset,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
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
            isEnabled: true,
            sortOrder: index == 0 ? 0 : index - 1,
            origin: origin,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

public enum OnboardingPresetPack: String, CaseIterable, Codable, Sendable {
    case starter
    case work
    case international
    case japanese
    case social
    case outreach
    case polish

    /// Which packs a language is actually offered.
    ///
    /// 简体中文 gets the Japanese list unchanged: that user writes Japanese and only
    /// reads the explanation in Chinese (§17), so 海外とのやり取り and 日本語を整える
    /// are as relevant to them as to a Japanese user. English drops both — one is
    /// 日↔英 translation and the other is Japanese proofreading — and puts Outreach
    /// and Polish in their place.
    public static func available(for language: AppLanguage) -> [OnboardingPresetPack] {
        language.writesJapanese
            ? [.starter, .work, .international, .japanese, .social]
            : [.starter, .work, .outreach, .polish, .social]
    }

    public var title: String {
        switch self {
        case .starter: return tr("まずは定番", "The everyday four", "先从常用的开始")
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
        templates.map {
            OnboardingButtonDraft(
                title: $0.title,
                prompt: $0.prompt,
                builtinKey: $0.builtinKey
            )
        }
    }

    private struct Template {
        let title: String
        let prompt: String
        var builtinKey: String? = nil
    }

    /// Titles are what the overlay bar draws, and the bar has **no overflow
    /// handling** (§4): the row is intrinsically sized and simply gets wider. The
    /// English titles are therefore kept to nine characters or fewer, which puts a
    /// four-button English row within a few points of a four-button Japanese one.
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
                    title: "敬語",
                    prompt: "次の文章を、日常でそのまま送れる自然でやわらかい丁寧語に変換してください。ビジネス敬語ではなく、相手に失礼がない普通の丁寧語にしてください。命令や指示は、やわらかいお願いの形にしてください。堅すぎる敬語は避け、出力は変換後の文章だけにしてください。",
                    builtinKey: "polite"
                ),
                Template(
                    title: "メール",
                    prompt: "次の文章を、日本のビジネスメールとしてそのまま送れる本文に整えてください。用件を先に示し、挨拶・本文・結びを自然に段落分けしてください。原文にない氏名・会社名・事実は作らず、件名・署名・拝啓・敬具は付けないでください。",
                    builtinKey: "email"
                ),
                Template(
                    title: "英訳",
                    prompt: "自然で読みやすい英語に翻訳してください。直訳ではなく、ネイティブが日常的に書く文体・語順にしてください。",
                    builtinKey: "translateToEnglish"
                ),
                Template(
                    title: "自然に",
                    prompt: "ネイティブが書いたような自然で読みやすい日本語に書き直してください。直訳調や不自然な言い回しは修正し、意味と話し手の雰囲気は保ってください。",
                    builtinKey: "natural"
                ),
            ]

        case .work:
            return [
                Template(
                    title: "社内チャット",
                    prompt: "次の文章を、SlackやTeamsなどの社内チャットでそのまま送れる、簡潔で感じのよい文章に書き直してください。メールのような挨拶や署名は付けず、用件を先に示し、丁寧さを保ちながら堅くしすぎないでください。"
                ),
                Template(
                    title: "上司向け",
                    prompt: "次の文章を、上司に失礼なく簡潔に伝わる文章に書き直してください。敬意は保ちつつ過度にへりくだらず、依頼や確認は相手が返答しやすい形にしてください。"
                ),
                Template(
                    title: "取引先",
                    prompt: "次の文章を、取引先にそのまま送れる自然なビジネス文に書き直してください。要点を明確にし、適切な敬語を使い、原文にない約束・事実・固有名詞は追加しないでください。"
                ),
                Template(
                    title: "会議要約",
                    prompt: "次の会議メモを、決定事項、未決事項、担当者と期限が分かる簡潔な要約にしてください。情報がない項目は作らず、重要な数字・日付・固有名詞は保持してください。"
                ),
            ]

        case .international:
            return [
                Template(
                    title: "英訳",
                    prompt: "自然で読みやすい英語に翻訳してください。直訳ではなく、ネイティブが日常的に書く文体・語順にしてください。",
                    builtinKey: "translateToEnglish"
                ),
                Template(
                    title: "和訳",
                    prompt: "次の文章を、翻訳調を残さない自然で読みやすい日本語に翻訳してください。意味、数字、日付、固有名詞を正確に保ってください。"
                ),
                Template(
                    title: "仕事英語",
                    prompt: "次の文章を、海外の同僚や取引先に送れる簡潔で自然なビジネス英語にしてください。直訳調を避け、丁寧で明確な表現にし、原文にない情報は追加しないでください。"
                ),
                Template(
                    title: "友達英語",
                    prompt: "次の文章を、英語話者の友達に送れる自然で親しみやすい英語にしてください。意味と温度感を保ち、教科書的または過度にくだけた表現は避けてください。"
                ),
            ]

        case .japanese:
            return [
                Template(
                    title: "校正",
                    prompt: "次の日本語の誤字、脱字、文法、助詞の誤りだけを修正してください。意味、語調、段落構成はできるだけ変えず、修正後の文章だけを出力してください。"
                ),
                Template(
                    title: "自然な日本語",
                    prompt: "次の文章を、日本語のネイティブが書いたような自然で読みやすい文章に書き直してください。不自然な語順や直訳調を直し、意味と話し手の意図は保ってください。"
                ),
                Template(
                    title: "やさしく",
                    prompt: "次の文章を、難しい語や長い文を避けた、やさしく分かりやすい日本語に書き直してください。情報を削りすぎず、一文を短くしてください。"
                ),
                Template(
                    title: "敬語",
                    prompt: "次の文章を、日常でそのまま送れる自然でやわらかい丁寧語に変換してください。命令や指示はやわらかいお願いの形にし、堅すぎる敬語は避けてください。",
                    builtinKey: "polite"
                ),
            ]

        case .social:
            return [
                Template(
                    title: "LINE",
                    prompt: "次の文章を、LINEでそのまま送れる短く自然なメッセージに書き直してください。会話らしいリズムと元の絵文字は保ち、メールのような堅い表現は避けてください。"
                ),
                Template(
                    title: "友達",
                    prompt: "次の文章を、親しい友達に送れる自然で親しみやすい口調に書き直してください。馴れ馴れしくしすぎず、意味と話し手らしさは保ってください。"
                ),
                Template(
                    title: "SNS投稿",
                    prompt: "次の文章を、SNSの投稿として読みやすく自然な文章に整えてください。冒頭で要点が伝わる構成にし、原文の事実と雰囲気は保ち、ハッシュタグは勝手に追加しないでください。"
                ),
                Template(
                    title: "コメント",
                    prompt: "次の文章を、SNSで面識のない相手にも失礼のない、親しみやすいコメントに書き直してください。過度に丁寧または馴れ馴れしい表現は避けてください。"
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
                    title: "Polite",
                    prompt: "Rewrite the text so it reads warm, courteous and professional. Soften blunt requests into considerate ones, keep it natural rather than stiff or old-fashioned, and do not add flattery. Output only the rewritten text.",
                    builtinKey: "polite"
                ),
                Template(
                    title: "Email",
                    prompt: "Rewrite the text as the body of a business email that could be sent as is. Lead with the point, break it into short natural paragraphs, and close politely. Do not add a subject line, signature or placeholder names, and do not invent facts that are not in the original.",
                    builtinKey: "email"
                ),
                Template(
                    title: "Shorten",
                    prompt: "Rewrite the text so it says the same thing in noticeably fewer words. Cut filler, hedging and repetition, keep every fact, name, number and date, and keep the tone the writer used."
                ),
                Template(
                    title: "Proofread",
                    prompt: "Correct only the spelling, grammar, punctuation and word-choice errors in the text. Keep the meaning, tone, structure and paragraph breaks as they are, and output only the corrected text."
                ),
            ]

        case .work:
            return [
                Template(
                    title: "Chat",
                    prompt: "Rewrite the text as a Slack or Teams message that can be sent as is: short, clear and friendly. Lead with the point, drop email greetings and sign-offs, and stay polite without being formal."
                ),
                Template(
                    title: "Manager",
                    prompt: "Rewrite the text as a message to the writer's manager. Be direct and respectful, put the ask or the status first, keep it brief, and make any request easy to answer. Do not over-apologise."
                ),
                Template(
                    title: "Client",
                    prompt: "Rewrite the text as a message to an external client. Be clear, professional and warm, make next steps explicit, and never add commitments, dates or names that are not in the original."
                ),
                Template(
                    title: "Recap",
                    prompt: "Turn the notes into a short recap that shows decisions, open questions, owners and deadlines. Do not invent anything that is missing; keep every number, date and name exactly as written."
                ),
            ]

        case .outreach:
            return [
                Template(
                    title: "Follow-up",
                    prompt: "Rewrite the text as a short follow-up to a message that has not been answered. Be friendly and low-pressure, restate the ask in one line, make it easy to reply, and do not guilt the reader or imply they were rude."
                ),
                Template(
                    title: "Intro",
                    prompt: "Rewrite the text as a first-contact message to someone the writer has not met. Open with why the writer is reaching out to this person specifically, keep it under a short paragraph, end with one clear and easy ask, and avoid hype and buzzwords."
                ),
                Template(
                    title: "Persuade",
                    prompt: "Rewrite the text to be more persuasive. Lead with the benefit to the reader, back the ask with the reasons already present in the original, and stay confident without exaggerating or inventing evidence."
                ),
                Template(
                    title: "Decline",
                    prompt: "Rewrite the text as a polite decline. Say no clearly so it cannot be misread as a maybe, keep the reason the writer gave, thank the reader, and leave the relationship intact. Do not promise future action the original did not offer."
                ),
            ]

        case .polish:
            return [
                Template(
                    title: "Grammar",
                    prompt: "Correct only the grammar, articles, prepositions, tense and spelling in the text. Keep the writer's wording, meaning and tone wherever it is already correct, and output only the corrected text."
                ),
                Template(
                    title: "Natural",
                    prompt: "Rewrite the text so it reads like a fluent native speaker wrote it. Fix awkward phrasing, word order and translated-sounding expressions, and keep the meaning and the writer's intent."
                ),
                Template(
                    title: "Simplify",
                    prompt: "Rewrite the text in plain English. Use shorter sentences and everyday words, drop jargon where a common word works, and keep all of the information."
                ),
                Template(
                    title: "Formal",
                    prompt: "Rewrite the text in formal written English suitable for an official or contractual context. Remove contractions and casual phrasing, stay precise, and do not add legal language or claims that are not in the original."
                ),
            ]

        case .social:
            return [
                Template(
                    title: "Friendly",
                    prompt: "Rewrite the text so it sounds warm and easy to read in a chat. Keep it conversational and keep any emoji the writer used, without becoming over-familiar."
                ),
                Template(
                    title: "Post",
                    prompt: "Rewrite the text as a social post that is easy to read: the point in the first line, short lines after it. Keep the facts and the writer's voice, and do not add hashtags that are not already there."
                ),
                Template(
                    title: "Comment",
                    prompt: "Rewrite the text as a friendly public comment to someone the writer does not know. Stay respectful and brief, and avoid both stiffness and over-familiarity."
                ),
                Template(
                    title: "Casual",
                    prompt: "Rewrite the text in a relaxed tone for a friend. Keep it natural and short, keep the meaning, and do not force slang."
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
