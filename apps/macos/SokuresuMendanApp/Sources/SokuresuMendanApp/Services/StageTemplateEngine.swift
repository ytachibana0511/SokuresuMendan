import Foundation

struct StageTemplateEngine {
    private let templates: [QuestionCategory: [String]] = [
        .selfIntro: [
            "- 結論: 現在の役割と得意領域を先に伝えます",
            "- 根拠: 直近の実績を1つ数字付きで述べます",
            "- 価値: この面談先で再現できる価値で締めます"
        ],
        .strengths: [
            "- 強みを1つに絞って明言します",
            "- 具体例として担当範囲と結果を30秒で示します",
            "- 入社後にどう活かすかまで繋げます"
        ],
        .motivation: [
            "- 志望理由を事業・技術・役割の順で短く説明します",
            "- 自分の経験と接点がある点を1つ示します",
            "- 入社後6か月で貢献したい項目を述べます"
        ],
        .experience: [
            "- 期間と役割を先に明示します",
            "- 課題→対応→成果を1セットで話します",
            "- 学びを次案件へどう適用したかで締めます"
        ],
        .incident: [
            "- まず事実と影響範囲を端的に伝えます",
            "- 初動で行った封じ込めを時系列で述べます",
            "- 再発防止を仕組み化した点を示します"
        ],
        .design: [
            "- 前提と非機能要件を最初に置きます",
            "- 代替案比較で採用理由を一言で示します",
            "- 運用・監視まで含めた設計意図で締めます"
        ],
        .testing: [
            "- テスト方針を粒度別に示します",
            "- 重要ケースを2つ挙げて優先理由を添えます",
            "- 自動化とリリースゲートを短く説明します"
        ],
        .teamwork: [
            "- チームでの役割と期待値調整を先に述べます",
            "- 衝突時の解決アプローチを具体例で示します",
            "- 成果をチーム全体に還元した点で締めます"
        ],
        .communication: [
            "- 相手別に伝え方を切り替える方針を示します",
            "- 認識ズレを減らすための手段を1つ挙げます",
            "- 進捗共有の頻度と形式を明確に述べます"
        ],
        .incidentResponse: [
            "- 検知から復旧までの優先順位を先に述べます",
            "- 指揮系統と連絡手順を簡潔に示します",
            "- 事後レビューで改善を定着させた点を話します"
        ],
        .performance: [
            "- ボトルネックの測定方法を最初に示します",
            "- 打ち手を低コスト順で提示します",
            "- 改善結果を数値で締めます"
        ],
        .security: [
            "- 脅威モデルを先に確認する姿勢を示します",
            "- 最小権限と監査ログの実装方針を述べます",
            "- 継続運用での見直しサイクルを添えます"
        ],
        .unknown: [
            "- まず結論を1文で答えます",
            "- 理由を1つ具体例付きで補足します",
            "- 最後に次アクションを短く示します"
        ]
    ]

    func immediateTemplate(for category: QuestionCategory, profileKeywords: [String]) -> String {
        let lines = templates[category] ?? templates[.unknown]!
        let keywordsLine: String
        if profileKeywords.isEmpty {
            keywordsLine = "- プロフィール要点: 実績キーワードを1つ差し込んでください"
        } else {
            keywordsLine = "- プロフィール要点: \(profileKeywords.prefix(2).joined(separator: " / "))"
        }
        return (Array(lines.prefix(2)) + [keywordsLine]).joined(separator: "\n")
    }
}
