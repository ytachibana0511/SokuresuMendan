import Foundation

final class QuestionDetector {
    private let strongQuestionMarkers: Set<String> = [
        "伺ってもよろしいでしょうか",
        "お伺いしてもよろしいでしょうか",
        "お伺いしてもよろしいですか",
        "伺ってもいいですか",
        "お聞きしてもよろしいでしょうか",
        "お聞きしてもよろしいですか",
        "お聞きしてもいいですか",
        "聞いてもいいですか",
        "聞いても大丈夫ですか",
        "質問してもいいですか",
        "質問よろしいですか",
        "ご質問よろしいでしょうか",
        "ちょっと質問いいですか",
        "一つ聞いてもいいですか",
        "一点お伺いしたいのですが",
        "一点だけお伺いしたいのですが",
        "一点確認させてください",
        "念のため確認させてください",
        "確認させていただけますか",
        "確認してもよろしいでしょうか",
        "確認してもいいですか",
        "ご確認いただけますか",
        "教えていただけますか",
        "教えていただけますでしょうか",
        "教えていただけませんか",
        "教えていただけないでしょうか",
        "ご教示いただけますか",
        "ご教示いただけますでしょうか",
        "ご教示いただけませんでしょうか",
        "共有いただけますか",
        "ご共有いただけますか",
        "ご説明いただけますか",
        "ご説明いただけますでしょうか",
        "補足いただけますか",
        "もう少し詳しく教えていただけますか",
        "もう少し詳しく伺えますか",
        "もう少し噛み砕いていただけますか",
        "具体例を挙げていただけますか",
        "具体例ってありますか",
        "例を一ついただけますか",
        "もう一度教えていただけますか",
        "改めて確認してもよろしいでしょうか",
        "差し支えなければ教えていただけますか",
        "差し支えなければ伺えますか",
        "可能であれば教えていただけますか",
        "もしよろしければお聞かせいただけますか",
        "お時間よろしいでしょうか",
        "お時間よろしいですか",
        "今お時間ありますか",
        "少しお時間いただけますか",
        "お手すきですか",
        "ご都合いかがでしょうか",
        "よろしいですか",
        "よろしいでしょうか",
        "いいですか",
        "大丈夫ですか",
        "問題ないですか",
        "差し支えないですか",
        "合っていますか",
        "合ってますか",
        "間違いないですか",
        "この理解で合っていますか",
        "この理解でいいですか",
        "という認識でよろしいですか",
        "という理解でよろしいですか",
        "ということで合っていますか",
        "ということでいいですか",
        "ということですか",
        "ってことなんですか",
        "ってことですか",
        "いかがですか",
        "いかがでしょうか",
        "どうですか",
        "どうでしょうか",
        "見解を伺えますか",
        "教えてもらえますか",
        "教えてもらえます？",
        "教えてもらえる？",
        "教えてくれますか",
        "教えてくれます？",
        "教えてくれる？",
        "教えてもらっていいですか",
        "説明してもらえます？",
        "説明してもらえる？",
        "共有してもらえますか",
        "見せてもらえますか",
        "見せてもらえます？",
        "見せてもらえる？",
        "いいっすか",
        "いいっすか？",
        "っすか",
        "っすか？",
        "大丈夫っすか",
        "大丈夫っすか？",
        // 互換維持で残す強シグナル
        "ですか",
        "ますか",
        "でしょうか",
        "教えて",
        "教えてください",
        "なぜ",
        "なんで",
        "理由は",
        "どうやって",
        "どのように",
        "何",
        "いつ",
        "どこ",
        "について",
        "できますか",
        "可能ですか",
        "お願いできますか",
        "おねがいします",
        "話してください",
        "話して",
        "説明してください",
        "聞かせてください",
        "お聞かせください",
        "どんな",
        "どういう",
        "って何",
        "ってどう",
        "ってどんな"
    ]

    private let contextQuestionMarkers: Set<String> = [
        "確認なんですが",
        "確認なんですけど",
        "確認なんですけども",
        "念のためですが",
        "念のためなんですが",
        "一点だけ確認で",
        "すみません、確認ですが",
        "すみません、ちょっと確認ですが",
        "すみません、質問ですが",
        "あの、確認なんですが",
        "えっと、確認なんですが",
        "あの、質問いいですか",
        "伺いたいことがありまして",
        "聞きたいことがありまして",
        "質問がありまして",
        "ちょっと聞きたいんですけど",
        "ちょっと伺いたいんですけど",
        "ちょっと質問なんですけど",
        "気になっているのは",
        "気になってまして",
        "ちょっと気になったんですが",
        "ちなみに",
        "ちなみにですが",
        "ちなみに伺うと",
        "ところで",
        "それで",
        "その場合",
        "もしそうだとすると",
        "ということは",
        "ってことは",
        "というのは",
        "っていうのは",
        "っていうのはつまり",
        "っていうのは具体的に",
        "あります？",
        "ありますかね",
        "あったりします？",
        "あったりしますか",
        "います？",
        "いますかね",
        "いらっしゃいます？",
        "いただけたりします？",
        "もらったりできます？",
        "とかありますか",
        "とかってありますか",
        "ってあります？",
        "ってありましたっけ",
        "ってことあります？",
        "ってことありますか",
        "そのへん",
        "志望動機は",
        "転職理由は",
        "これまでの経歴は",
        "直近の担当は",
        "役割は",
        "担当範囲は",
        "開発規模は",
        "チーム規模は",
        "人数は",
        "期間は",
        "使用技術は",
        "言語は",
        "フレームワークは",
        "設計方針は",
        "テスト方針は",
        "レビュー体制は",
        "CI/CDは",
        "運用体制は",
        "障害対応は",
        "強みは",
        "弱みは",
        "どうなんです",
        "どうなんでしょう",
        "どうですかね",
        "いかがでしょう"
    ]

    private let weakQuestionMarkers: Set<String> = [
        "だよね？", "だよね?", "だよね",
        "ですよね？", "ですよね?", "ですよね",
        "でしょ？", "でしょ?", "でしょ",
        "っしょ？", "っしょ?", "っしょ",
        "じゃない？", "じゃない?", "じゃない",
        "じゃね？", "じゃね?", "じゃね",
        "だっけ？", "だっけ?", "だっけ",
        "だったっけ？", "だったっけ",
        "いいんだっけ？", "いいんだっけ",
        "どっちだっけ？", "どっちだっけ",
        "なんだっけ？", "なんだっけ",
        "かなぁ", "かなあ", "かなー", "かな…", "かなぁ？", "かなあ？",
        "かも？", "かも?", "かもね？", "かもね",
        "よね？", "よね", "ね？", "ね?",
        "ってことだよね", "ってことじゃない？", "ってことかも", "ってことだっけ", "ってことになる？",
        "って感じだよね",
        "わかる？", "わかる?", "わかります？", "わかります?",
        "あり？", "なし？",
        "いける？", "いけます？",
        "どう思います？", "どう思います?",
        "なの？", "なの?", "なん？", "なん?", "の？", "の?",
        "なんでだっけ？",
        "いけるっしょ？",
        "ってアリ？", "ってなし？",
        "ってこと？",
        // 既存の口語語尾
        "かな", "かな?", "かな？", "って感じ", "って感じ?", "って感じ？", "くれる", "くれる?", "くれる？", "もらえる", "もらえる?", "もらえる？"
    ]

    private let excludeMarkers: Set<String> = [
        "そうですか",
        "そうなんですね",
        "そうなんだ",
        "なるほど",
        "なるほどですね",
        "了解です",
        "承知しました",
        "かしこまりました",
        "わかりました",
        "了解しました",
        "承知です",
        "はい",
        "ええ",
        "うん",
        "なるほど、はい",
        "ありがとうございます",
        "ありがとうございます！",
        "助かります",
        "すみません",
        "失礼します",
        "お疲れ様です",
        "よろしくお願いします",
        "よろしくお願いいたします",
        "よろしくお願いします！",
        "お願いいたします",
        "以上です",
        "以上になります",
        "以上となります",
        "ということです",
        "ということですね",
        "そういうことですね",
        "そういうことか",
        "そうですね",
        "そうなんですよ",
        "そうなんです",
        "ですね",
        "ですよ",
        "と思います",
        "と思っています",
        "という感じです"
    ]

    private let englishStrongMarkers: Set<String> = [
        "what", "why", "how", "can you", "could you", "would you", "walk me through"
    ]

    private let categoryRules: [QuestionCategory: [String]] = [
        .selfIntro: ["自己紹介", "紹介", "これまで", "経歴"],
        .strengths: ["強み", "得意", "長所"],
        .motivation: ["志望", "なぜ当社", "入社", "転職理由"],
        .experience: ["経験", "担当", "実績", "プロジェクト"],
        .incident: ["炎上", "トラブル", "失敗", "リカバリ"],
        .design: ["設計", "アーキテクチャ", "構成", "技術選定"],
        .testing: ["テスト", "品質", "検証", "QA"],
        .teamwork: ["チーム", "協業", "連携", "リード"],
        .communication: ["コミュニケーション", "説明", "共有", "合意"],
        .incidentResponse: ["障害", "インシデント", "復旧", "オンコール"],
        .performance: ["パフォーマンス", "性能", "レイテンシ", "最適化"],
        .security: ["セキュリティ", "脆弱性", "認証", "権限"]
    ]

    private let fillerPrefixPattern = #"^(?:(?:えっと|えーと|あの|その|まあ|んーと)\s*[,、]?\s*)+"#
    private let strongTailPattern = #"(?:\?|？|いいっすか(?:\?|？)?|大丈夫っすか(?:\?|？)?|っすか(?:\?|？)?|よろしい(?:でしょうか|ですか)|いいですか|大丈夫ですか|問題ないですか|差し支えないですか|合って(?:ます)?か|間違いないですか|ってこと(?:なんですか|ですか))\s*$"#
    private let requestLikePattern = #"(?:教えて|確認|説明|共有|補足).{0,10}(?:いただけ(?:ます|ません)か|もらえます(?:か)?|くれます(?:か)?|いただけますでしょうか)\s*$"#

    private let deltaThreshold = 3.0
    private let completedThreshold = 3.0
    private let earlyCommitThreshold = 5.0

    private var recentQuestions: [String] = []
    private let recentCapacity = 8

    func isQuestionLike(_ rawText: String) -> Bool {
        let normalized = normalize(rawText)
        guard normalized.count >= 4 else {
            return false
        }

        let scoreResult = evaluateScore(for: normalized, isCompleted: true)
        return scoreResult.rawScore >= completedThreshold
    }

    func evaluateDelta(buffer: String, latestDelta _: String) -> DetectedQuestion? {
        let text = normalize(buffer)
        guard text.count >= 4 else {
            return nil
        }

        let scoreResult = evaluateScore(for: text, isCompleted: false)
        guard scoreResult.rawScore >= deltaThreshold else {
            return nil
        }

        let (category, matchedKeywords) = inferCategory(from: text)
        let confidence = confidence(from: scoreResult.rawScore)
        let markerMatches = Array(Set(scoreResult.matchedMarkers + matchedKeywords))
        let reason = buildReason(prefix: "delta", scoreResult: scoreResult, categoryKeywords: matchedKeywords)

        return DetectedQuestion(
            text: text,
            category: category,
            confidence: confidence,
            matchedKeywords: markerMatches,
            reason: reason,
            timestamp: .now
        )
    }

    func finalizeQuestion(_ completedText: String) -> DetectedQuestion? {
        let normalized = normalize(completedText)
        guard !normalized.isEmpty else {
            return nil
        }

        let scoreResult = evaluateScore(for: normalized, isCompleted: true)
        guard scoreResult.rawScore >= completedThreshold else {
            return nil
        }

        guard !isDuplicate(normalized) else {
            return nil
        }

        let (category, matchedKeywords) = inferCategory(from: normalized)
        let confidence = confidence(from: scoreResult.rawScore)
        let markerMatches = Array(Set(scoreResult.matchedMarkers + matchedKeywords))
        let reason = buildReason(prefix: "completed", scoreResult: scoreResult, categoryKeywords: matchedKeywords)

        remember(normalized)
        return DetectedQuestion(
            text: normalized,
            category: category,
            confidence: confidence,
            matchedKeywords: markerMatches,
            reason: reason,
            timestamp: .now
        )
    }

    func shouldEarlyCommit(_ detection: DetectedQuestion) -> Bool {
        let scoreResult = evaluateScore(for: detection.text, isCompleted: false)
        guard scoreResult.rawScore >= earlyCommitThreshold else {
            return false
        }
        guard detection.text.count >= 8 else {
            return false
        }

        return scoreResult.punctuationMatched
            || scoreResult.strongTailMatched
            || scoreResult.hasNearStrongMarker
    }

    private func inferCategory(from text: String) -> (QuestionCategory, [String]) {
        for (category, keywords) in categoryRules {
            let matched = keywords.filter { text.localizedCaseInsensitiveContains($0) }
            if !matched.isEmpty {
                return (category, matched)
            }
        }
        return (.unknown, [])
    }

    private func evaluateScore(for text: String, isCompleted: Bool) -> ScoreResult {
        let strippedText = stripFillerPrefix(text)
        let lowercase = strippedText.lowercased()

        var rawScore = 0.0
        var matchedStrong: [String] = []
        var matchedContext: [String] = []
        var matchedWeak: [String] = []
        var hasNearStrongMarker = false

        rawScore += accumulateScore(
            text: strippedText,
            markers: strongQuestionMarkers,
            baseWeight: 3,
            matched: &matchedStrong,
            hasNearStrongMarker: &hasNearStrongMarker,
            trackNearStrong: true
        )

        rawScore += accumulateScore(
            text: lowercase,
            markers: englishStrongMarkers,
            baseWeight: 3,
            matched: &matchedStrong,
            hasNearStrongMarker: &hasNearStrongMarker,
            trackNearStrong: true
        )

        rawScore += accumulateScore(
            text: strippedText,
            markers: contextQuestionMarkers,
            baseWeight: 2,
            matched: &matchedContext,
            hasNearStrongMarker: &hasNearStrongMarker,
            trackNearStrong: false
        )

        rawScore += accumulateScore(
            text: strippedText,
            markers: weakQuestionMarkers,
            baseWeight: 1,
            matched: &matchedWeak,
            hasNearStrongMarker: &hasNearStrongMarker,
            trackNearStrong: false
        )

        let punctuationMatched = strippedText.contains("?") || strippedText.contains("？")
        if punctuationMatched {
            rawScore += 4
        }

        let strongTailMatched = strippedText.range(of: strongTailPattern, options: .regularExpression) != nil
        if strongTailMatched {
            rawScore += 3
        }

        let requestLikeMatched = strippedText.range(of: requestLikePattern, options: .regularExpression) != nil
        if requestLikeMatched {
            rawScore += 2
        }

        let nounWaCompletedBoostApplied = isCompleted && hasNounWaEnding(strippedText)
        if nounWaCompletedBoostApplied {
            rawScore += 2
        }

        let casualEndingBoostApplied = isCompleted && hasCasualQuestionEnding(strippedText)
        if casualEndingBoostApplied {
            rawScore += 2
        }

        let excludedShortUtteranceApplied = isExcludedShortUtterance(strippedText)
        if excludedShortUtteranceApplied {
            rawScore -= 5
        }

        if rawScore < 0 {
            rawScore = 0
        }

        let matchedMarkers = Array(Set(matchedStrong + matchedContext + matchedWeak)).sorted()

        return ScoreResult(
            rawScore: rawScore,
            matchedMarkers: matchedMarkers,
            matchedStrong: Array(Set(matchedStrong)).sorted(),
            matchedContext: Array(Set(matchedContext)).sorted(),
            matchedWeak: Array(Set(matchedWeak)).sorted(),
            punctuationMatched: punctuationMatched,
            strongTailMatched: strongTailMatched,
            requestLikeMatched: requestLikeMatched,
            hasNearStrongMarker: hasNearStrongMarker,
            nounWaCompletedBoostApplied: nounWaCompletedBoostApplied,
            casualEndingBoostApplied: casualEndingBoostApplied,
            excludedShortUtteranceApplied: excludedShortUtteranceApplied
        )
    }

    private func accumulateScore(
        text: String,
        markers: Set<String>,
        baseWeight: Double,
        matched: inout [String],
        hasNearStrongMarker: inout Bool,
        trackNearStrong: Bool
    ) -> Double {
        var score = 0.0
        for marker in markers {
            guard let distance = nearestDistanceFromEnd(of: marker, in: text) else {
                continue
            }
            let decay = distanceDecay(distance)
            guard decay > 0 else {
                continue
            }
            score += baseWeight * decay
            matched.append(marker)
            if trackNearStrong, distance <= 8 {
                hasNearStrongMarker = true
            }
        }
        return score
    }

    private func nearestDistanceFromEnd(of marker: String, in text: String) -> Int? {
        let nsText = text as NSString
        var searchRange = NSRange(location: 0, length: nsText.length)
        var nearest: Int?

        while searchRange.location < nsText.length {
            let found = nsText.range(of: marker, options: [], range: searchRange)
            if found.location == NSNotFound {
                break
            }

            let endPosition = found.location + found.length
            let distance = nsText.length - endPosition
            if let existingNearest = nearest {
                if distance < existingNearest {
                    nearest = distance
                }
            } else {
                nearest = distance
            }

            let nextLocation = found.location + max(found.length, 1)
            if nextLocation >= nsText.length {
                break
            }
            searchRange = NSRange(location: nextLocation, length: nsText.length - nextLocation)
        }

        return nearest
    }

    private func distanceDecay(_ distance: Int) -> Double {
        if distance <= 8 {
            return 1.0
        }
        if distance <= 20 {
            return 0.5
        }
        return 0
    }

    private func stripFillerPrefix(_ text: String) -> String {
        text.replacingOccurrences(of: fillerPrefixPattern, with: "", options: .regularExpression)
    }

    private func hasNounWaEnding(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 28 {
            return false
        }
        return trimmed.hasSuffix("は") || trimmed.hasSuffix("って")
    }

    private func hasCasualQuestionEnding(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("かな")
            || trimmed.hasSuffix("かな?")
            || trimmed.hasSuffix("かな？")
            || trimmed.hasSuffix("かも？")
            || trimmed.hasSuffix("かも?")
            || trimmed.hasSuffix("くれる")
            || trimmed.hasSuffix("くれる？")
            || trimmed.hasSuffix("くれる?")
            || trimmed.hasSuffix("もらえる")
            || trimmed.hasSuffix("もらえる？")
            || trimmed.hasSuffix("もらえる?")
    }

    private func isExcludedShortUtterance(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 24 else {
            return false
        }
        return excludeMarkers.contains(trimmed)
    }

    private func confidence(from rawScore: Double) -> Double {
        min(0.99, max(0.05, rawScore / 10.0))
    }

    private func buildReason(prefix: String, scoreResult: ScoreResult, categoryKeywords: [String]) -> String {
        var parts: [String] = []
        parts.append("\(prefix) score=\(String(format: "%.2f", scoreResult.rawScore))")

        let markerPreview = (scoreResult.matchedMarkers + categoryKeywords).prefix(5).joined(separator: ", ")
        if !markerPreview.isEmpty {
            parts.append("markers=\(markerPreview)")
        }

        if scoreResult.strongTailMatched {
            parts.append("strongTail")
        }
        if scoreResult.punctuationMatched {
            parts.append("punctuation")
        }
        if scoreResult.hasNearStrongMarker {
            parts.append("nearStrong")
        }
        if scoreResult.nounWaCompletedBoostApplied {
            parts.append("nounWaBoost")
        }
        if scoreResult.casualEndingBoostApplied {
            parts.append("casualBoost")
        }
        if scoreResult.excludedShortUtteranceApplied {
            parts.append("excludePenalty")
        }

        return parts.joined(separator: " | ")
    }

    private func normalize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func remember(_ question: String) {
        recentQuestions.append(question)
        if recentQuestions.count > recentCapacity {
            recentQuestions.removeFirst(recentQuestions.count - recentCapacity)
        }
    }

    private func isDuplicate(_ question: String) -> Bool {
        recentQuestions.contains { recent in
            if recent == question {
                return true
            }
            return similarity(lhs: recent, rhs: question) >= 0.82
        }
    }

    private func similarity(lhs: String, rhs: String) -> Double {
        let leftTokens = lhs.lowercased().split(separator: " ").map(String.init)
        let rightTokens = rhs.lowercased().split(separator: " ").map(String.init)

        if leftTokens.count > 1 || rightTokens.count > 1 {
            let left = Set(leftTokens)
            let right = Set(rightTokens)
            guard !left.isEmpty || !right.isEmpty else { return 1.0 }
            let intersection = left.intersection(right).count
            let union = left.union(right).count
            guard union > 0 else { return 0 }
            return Double(intersection) / Double(union)
        }

        let leftBigrams = bigrams(of: lhs)
        let rightBigrams = bigrams(of: rhs)
        guard !leftBigrams.isEmpty || !rightBigrams.isEmpty else { return 1.0 }
        let intersection = leftBigrams.intersection(rightBigrams).count
        let union = leftBigrams.union(rightBigrams).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private func bigrams(of text: String) -> Set<String> {
        let chars = Array(text.lowercased())
        guard chars.count >= 2 else {
            return Set([text.lowercased()])
        }

        var grams = Set<String>()
        for index in 0..<(chars.count - 1) {
            grams.insert(String(chars[index...index + 1]))
        }
        return grams
    }

}

private struct ScoreResult {
    let rawScore: Double
    let matchedMarkers: [String]
    let matchedStrong: [String]
    let matchedContext: [String]
    let matchedWeak: [String]
    let punctuationMatched: Bool
    let strongTailMatched: Bool
    let requestLikeMatched: Bool
    let hasNearStrongMarker: Bool
    let nounWaCompletedBoostApplied: Bool
    let casualEndingBoostApplied: Bool
    let excludedShortUtteranceApplied: Bool
}
