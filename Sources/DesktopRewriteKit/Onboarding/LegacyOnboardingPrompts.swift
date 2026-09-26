import Foundation

// Preserve exact recognition of previously shipped presets without rewriting saved buttons.
enum LegacyOnboardingPrompts {
    private static let japanese: [String: String] = [
        "自然で読みやすい日本語に整えてください。": "natural_japanese",
        "自然な英語に翻訳してください。": "translate_english",
        "そのまま送れる日本語のビジネスメール本文に整えてください。": "email",
        "自然で丁寧な敬語にしてください。": "polite",
        "次の文章を、日常でそのまま送れる自然でやわらかい丁寧語に変換してください。ビジネス敬語ではなく、相手に失礼がない普通の丁寧語にしてください。命令や指示は、やわらかいお願いの形にしてください。堅すぎる敬語は避け、出力は変換後の文章だけにしてください。": "polite",
        "次の文章を、日本のビジネスメールとしてそのまま送れる本文に整えてください。用件を先に示し、挨拶・本文・結びを自然に段落分けしてください。原文にない氏名・会社名・事実は作らず、件名・署名・拝啓・敬具は付けないでください。": "email",
        "自然で読みやすい英語に翻訳してください。直訳ではなく、ネイティブが日常的に書く文体・語順にしてください。": "translate_english",
        "ネイティブが書いたような自然で読みやすい日本語に書き直してください。直訳調や不自然な言い回しは修正し、意味と話し手の雰囲気は保ってください。": "natural_japanese",
        "次の文章を、SlackやTeamsなどの社内チャットでそのまま送れる、簡潔で感じのよい文章に書き直してください。メールのような挨拶や署名は付けず、用件を先に示し、丁寧さを保ちながら堅くしすぎないでください。": "work_chat",
        "次の文章を、上司に失礼なく簡潔に伝わる文章に書き直してください。敬意は保ちつつ過度にへりくだらず、依頼や確認は相手が返答しやすい形にしてください。": "manager_message",
        "次の文章を、取引先にそのまま送れる自然なビジネス文に書き直してください。要点を明確にし、適切な敬語を使い、原文にない約束・事実・固有名詞は追加しないでください。": "client_message",
        "次の会議メモを、決定事項、未決事項、担当者と期限が分かる簡潔な要約にしてください。情報がない項目は作らず、重要な数字・日付・固有名詞は保持してください。": "meeting_recap",
        "次の文章を、翻訳調を残さない自然で読みやすい日本語に翻訳してください。意味、数字、日付、固有名詞を正確に保ってください。": "translate_japanese",
        "次の文章を、海外の同僚や取引先に送れる簡潔で自然なビジネス英語にしてください。直訳調を避け、丁寧で明確な表現にし、原文にない情報は追加しないでください。": "business_english",
        "次の文章を、英語話者の友達に送れる自然で親しみやすい英語にしてください。意味と温度感を保ち、教科書的または過度にくだけた表現は避けてください。": "friend_english",
        "次の日本語の誤字、脱字、文法、助詞の誤りだけを修正してください。意味、語調、段落構成はできるだけ変えず、修正後の文章だけを出力してください。": "proofread_japanese",
        "次の文章を、日本語のネイティブが書いたような自然で読みやすい文章に書き直してください。不自然な語順や直訳調を直し、意味と話し手の意図は保ってください。": "natural_japanese",
        "次の文章を、難しい語や長い文を避けた、やさしく分かりやすい日本語に書き直してください。情報を削りすぎず、一文を短くしてください。": "simplify_japanese",
        "次の文章を、日常でそのまま送れる自然でやわらかい丁寧語に変換してください。命令や指示はやわらかいお願いの形にし、堅すぎる敬語は避けてください。": "polite",
        "次の文章を、LINEでそのまま送れる短く自然なメッセージに書き直してください。会話らしいリズムと元の絵文字は保ち、メールのような堅い表現は避けてください。": "line_message",
        "次の文章を、親しい友達に送れる自然で親しみやすい口調に書き直してください。馴れ馴れしくしすぎず、意味と話し手らしさは保ってください。": "friend_message",
        "次の文章を、SNSの投稿として読みやすく自然な文章に整えてください。冒頭で要点が伝わる構成にし、原文の事実と雰囲気は保ち、ハッシュタグは勝手に追加しないでください。": "social_post",
        "次の文章を、SNSで面識のない相手にも失礼のない、親しみやすいコメントに書き直してください。過度に丁寧または馴れ馴れしい表現は避けてください。": "social_comment",
    ]

    private static let english: [String: String] = [
        "Fix spelling and grammar while keeping my voice.": "proofread_english",
        "Make this shorter while keeping the main points.": "shorten",
        "Turn this into a clear, professional email body.": "email",
        "Make this sound polite and natural.": "polite",
        "Rewrite the text so it reads warm, courteous and professional. Soften blunt requests into considerate ones, keep it natural rather than stiff or old-fashioned, and do not add flattery. Output only the rewritten text.": "polite",
        "Rewrite the text as the body of a business email that could be sent as is. Lead with the point, break it into short natural paragraphs, and close politely. Do not add a subject line, signature or placeholder names, and do not invent facts that are not in the original.": "email",
        "Rewrite the text so it says the same thing in noticeably fewer words. Cut filler, hedging and repetition, keep every fact, name, number and date, and keep the tone the writer used.": "shorten",
        "Correct only the spelling, grammar, punctuation and word-choice errors in the text. Keep the meaning, tone, structure and paragraph breaks as they are, and output only the corrected text.": "proofread_english",
        "Rewrite the text as a Slack or Teams message that can be sent as is: short, clear and friendly. Lead with the point, drop email greetings and sign-offs, and stay polite without being formal.": "work_chat",
        "Rewrite the text as a message to the writer's manager. Be direct and respectful, put the ask or the status first, keep it brief, and make any request easy to answer. Do not over-apologise.": "manager_message",
        "Rewrite the text as a message to an external client. Be clear, professional and warm, make next steps explicit, and never add commitments, dates or names that are not in the original.": "client_message",
        "Turn the notes into a short recap that shows decisions, open questions, owners and deadlines. Do not invent anything that is missing; keep every number, date and name exactly as written.": "meeting_recap",
        "Rewrite the text as a short follow-up to a message that has not been answered. Be friendly and low-pressure, restate the ask in one line, make it easy to reply, and do not guilt the reader or imply they were rude.": "follow_up",
        "Rewrite the text as a first-contact message to someone the writer has not met. Open with why the writer is reaching out to this person specifically, keep it under a short paragraph, end with one clear and easy ask, and avoid hype and buzzwords.": "first_contact",
        "Rewrite the text to be more persuasive. Lead with the benefit to the reader, back the ask with the reasons already present in the original, and stay confident without exaggerating or inventing evidence.": "persuasive",
        "Rewrite the text as a polite decline. Say no clearly so it cannot be misread as a maybe, keep the reason the writer gave, thank the reader, and leave the relationship intact. Do not promise future action the original did not offer.": "decline",
        "Correct only the grammar, articles, prepositions, tense and spelling in the text. Keep the writer's wording, meaning and tone wherever it is already correct, and output only the corrected text.": "grammar",
        "Rewrite the text so it reads like a fluent native speaker wrote it. Fix awkward phrasing, word order and translated-sounding expressions, and keep the meaning and the writer's intent.": "natural_english",
        "Rewrite the text in plain English. Use shorter sentences and everyday words, drop jargon where a common word works, and keep all of the information.": "simplify_english",
        "Rewrite the text in formal written English suitable for an official or contractual context. Remove contractions and casual phrasing, stay precise, and do not add legal language or claims that are not in the original.": "formal_english",
        "Rewrite the text so it sounds warm and easy to read in a chat. Keep it conversational and keep any emoji the writer used, without becoming over-familiar.": "friendly_chat",
        "Rewrite the text as a social post that is easy to read: the point in the first line, short lines after it. Keep the facts and the writer's voice, and do not add hashtags that are not already there.": "social_post",
        "Rewrite the text as a friendly public comment to someone the writer does not know. Stay respectful and brief, and avoid both stiffness and over-familiarity.": "social_comment",
        "Rewrite the text in a relaxed tone for a friend. Keep it natural and short, keep the meaning, and do not force slang.": "casual_message",
    ]

    static func bodies(writtenIn language: AppLanguage) -> Set<String> {
        Set((language.writesJapanese ? japanese : english).keys)
    }

    static func analyticsKey(for body: String) -> String? {
        japanese[body] ?? english[body]
    }
}
