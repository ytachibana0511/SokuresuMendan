import XCTest
@testable import SokuresuMendanApp

final class StageJSONParserTests: XCTestCase {
    func testParseStage1() throws {
        let raw = #"{"answer_10s":"結論から言うと、要件整理を先に行い短いサイクルで実装します。","keywords":["要件整理","短サイクル"],"assumptions":["バックエンド案件を想定"]}"#

        let parsed = try StageJSONParser.parseStage1(raw)

        XCTAssertEqual(parsed.answer_10s, "結論から言うと、要件整理を先に行い短いサイクルで実装します。")
        XCTAssertEqual(parsed.keywords.count, 2)
        XCTAssertEqual(parsed.assumptions.first, "バックエンド案件を想定")
    }

    func testParseStage2() throws {
        let raw = #"{"answer_30s":"要件定義で非機能要件を先に確定し、計測を前提に設計しました。","followups":[{"question":"再発防止は？","suggested_answer":"監視とポストモーテムで運用へ組み込みました。"}]}"#

        let parsed = try StageJSONParser.parseStage2(raw)

        XCTAssertEqual(parsed.answer_30s, "要件定義で非機能要件を先に確定し、計測を前提に設計しました。")
        XCTAssertEqual(parsed.followups.count, 1)
        XCTAssertEqual(parsed.followups.first?.question, "再発防止は？")
    }
}
