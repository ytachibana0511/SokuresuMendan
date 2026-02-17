import Foundation

enum ProxyStatus: String {
    case ok = "OK"
    case ng = "NG"
}

enum StreamStatus: String {
    case disconnected = "未接続"
    case connecting = "接続中"
    case listening = "聞き取り中"
    case idle = "待機中"
    case error = "エラー"
}

enum GenerationStatus: Equatable {
    case idle
    case waiting
    case streaming
    case done
    case error(String)

    var label: String {
        switch self {
        case .idle:
            return "待機中"
        case .waiting:
            return "準備中"
        case .streaming:
            return "生成中"
        case .done:
            return "完了"
        case .error:
            return "エラー"
        }
    }
}

enum InputSource: String, CaseIterable, Identifiable {
    case systemAudio = "システム音声（BlackHole等）"
    case microphone = "マイク"
    case text = "テキスト入力"

    var id: String { rawValue }
}

enum QuestionCategory: String, CaseIterable, Codable {
    case selfIntro = "自己紹介"
    case strengths = "強み"
    case motivation = "志望動機"
    case experience = "経験"
    case incident = "炎上対応"
    case design = "設計"
    case testing = "テスト"
    case teamwork = "チーム"
    case communication = "コミュニケーション"
    case incidentResponse = "障害対応"
    case performance = "パフォーマンス"
    case security = "セキュリティ"
    case unknown = "その他"
}

struct LatencyMetrics {
    var detectionMs: Int?
    var stage1FirstTokenMs: Int?
}

struct DetectedQuestion {
    let text: String
    let category: QuestionCategory
    let confidence: Double
    let matchedKeywords: [String]
    let reason: String
    let timestamp: Date
}

struct FollowupQA: Codable, Identifiable, Equatable {
    let question: String
    let suggested_answer: String

    var id: String { question + suggested_answer }
}

struct Stage1Payload: Codable, Equatable {
    let answer_10s: String
    let keywords: [String]
    let assumptions: [String]
}

struct Stage2Payload: Codable, Equatable {
    let answer_30s: String
    let followups: [FollowupQA]
}

struct Stage1GenerateRequest: Codable {
    let question: String
    let category: QuestionCategory
    let profile_summary: String
    let profile_bullets: [String]
    let language: String
}

struct Stage2GenerateRequest: Codable {
    let question: String
    let category: QuestionCategory
    let stage1_answer: String
    let profile_summary: String
    let profile_bullets: [String]
    let language: String
}

struct CandidateProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var rawText: String
    var summary: String
    var keywords: [String]
    var updatedAt: Date
}

struct StageOutput {
    var stage0Template: String = ""
    var stage1: Stage1Payload?
    var stage2: Stage2Payload?
}

struct AnswerHistoryEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let question: String
    let category: QuestionCategory
    var stage0Template: String
    var answer10s: String
    var answer30s: String
    var followups: [FollowupQA]
}

struct TranscriptSnapshot {
    var liveTranscript: String = ""
    var provisionalQuestion: String = ""
    var finalizedQuestion: String = ""
}

struct ProxyHealth: Codable {
    let ok: Bool
    let version: String?
}

enum TranscribeEvent {
    case status(String)
    case delta(String)
    case completed(String)
    case committed(String)
    case error(String)
}

struct StageStreamEvent<T: Decodable>: Decodable {
    let type: String
    let delta: String?
    let result: T?
    let error: String?
}
