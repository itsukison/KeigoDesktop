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

    public var title: String {
        switch self {
        case .starter: return "まずは定番"
        case .work: return "仕事の連絡"
        case .international: return "海外とのやり取り"
        case .japanese: return "日本語を整える"
        case .social: return "友達・SNS"
        }
    }

    public var caption: String {
        switch self {
        case .starter: return "よく使われる4つから始める"
        case .work: return "社内・上司・取引先への文章を整える"
        case .international: return "日本語と英語を場面に合わせて訳す"
        case .japanese: return "誤りを直し、自然で読みやすい日本語に"
        case .social: return "LINEやSNSで自然に伝わる文章に"
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

    private var templates: [Template] {
        switch self {
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
}

public enum OnboardingPracticeSample {
    public static func text(for prompt: UserPrompt) -> String {
        let clue = "\(prompt.title) \(prompt.prompt)".lowercased()

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
}
