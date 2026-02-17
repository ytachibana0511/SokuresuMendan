import XCTest
@testable import SokuresuMendanApp

final class QuestionDetectorTests: XCTestCase {
    func testDeltaDetectionDetectsCategoryAndQuestion() {
        let detector = QuestionDetector()
        let buffer = "あなたの設計の進め方を教えてください"

        let detected = detector.evaluateDelta(buffer: buffer, latestDelta: "教えてください")

        XCTAssertNotNil(detected)
        XCTAssertEqual(detected?.category, .design)
        XCTAssertGreaterThanOrEqual(detected?.confidence ?? 0, 0.55)
    }

    func testFinalizeSuppressesSimilarDuplicate() {
        let detector = QuestionDetector()
        let first = detector.finalizeQuestion("なぜこの設計を選びましたか？")
        XCTAssertNotNil(first)

        let duplicate = detector.finalizeQuestion("なぜこの設計を選びましたか？")
        XCTAssertNil(duplicate)
    }

    func testEarlyCommitRule() {
        let detector = QuestionDetector()
        let detection = DetectedQuestion(
            text: "この障害対応の初動、どうやって進めましたか？",
            category: .incidentResponse,
            confidence: 0.85,
            matchedKeywords: ["障害", "どうやって"],
            reason: "test",
            timestamp: .now
        )

        XCTAssertTrue(detector.shouldEarlyCommit(detection))
    }

    func testFinalizeSkipsNonQuestionSentence() {
        let detector = QuestionDetector()
        let detected = detector.finalizeQuestion("今日は自己紹介とこれまでの経歴を共有します")
        XCTAssertNil(detected)
    }

    func testDetectsExpandedQuestionMarkers() {
        let detector = QuestionDetector()

        let aboutDetected = detector.finalizeQuestion("この設計について詳しく教えてください")
        XCTAssertNotNil(aboutDetected)

        let reasonDetected = detector.finalizeQuestion("なんでこの構成を選んだんですか")
        XCTAssertNotNil(reasonDetected)

        let possibleDetected = detector.finalizeQuestion("この要件は明日までに対応可能ですか")
        XCTAssertNotNil(possibleDetected)

        let requestDetected = detector.finalizeQuestion("まず自己PRをお願いします")
        XCTAssertNil(requestDetected)

        let casualDetected = detector.finalizeQuestion("この進め方ってどんな感じ？")
        XCTAssertNotNil(casualDetected)

        let endingDetected = detector.finalizeQuestion("この件、今日中にいけるかな")
        XCTAssertNotNil(endingDetected)
    }

    func testDetectsNounWaQuestionOnCompleted() {
        let detector = QuestionDetector()

        let deltaDetected = detector.evaluateDelta(buffer: "志望動機は", latestDelta: "は")
        XCTAssertNil(deltaDetected)

        let completedDetected = detector.finalizeQuestion("志望動機は")
        XCTAssertNotNil(completedDetected)
        XCTAssertEqual(completedDetected?.category, .motivation)
    }
}
