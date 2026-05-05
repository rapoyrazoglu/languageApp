import XCTest
@testable import PaktlyKit

final class TypingAcceptanceTests: XCTestCase {
    private func data(answer: String, alternatives: [String] = [], caseSensitive: Bool = false) -> TypingData {
        TypingData(
            prompt: ExerciseMedia(),
            answer: answer,
            acceptedAlternatives: alternatives,
            caseSensitive: caseSensitive
        )
    }

    func testCanonicalAnswer_MatchesExactly() {
        XCTAssertTrue(TypingExerciseView.isAcceptable(input: "konnichiwa", data: data(answer: "konnichiwa")))
    }

    func testCaseInsensitive_ByDefault() {
        XCTAssertTrue(TypingExerciseView.isAcceptable(input: "KonnichiWa", data: data(answer: "konnichiwa")))
    }

    func testWhitespaceTrim_BothEnds() {
        XCTAssertTrue(TypingExerciseView.isAcceptable(input: "   konnichiwa   ", data: data(answer: "konnichiwa")))
    }

    func testCaseSensitive_FlagRejectsCaseDiff() {
        XCTAssertFalse(
            TypingExerciseView.isAcceptable(
                input: "Konnichiwa",
                data: data(answer: "konnichiwa", caseSensitive: true)
            )
        )
    }

    func testAcceptedAlternatives_AreHonoured() {
        let d = data(answer: "こんにちは", alternatives: ["コンニチハ", "konnichiwa"])
        XCTAssertTrue(TypingExerciseView.isAcceptable(input: "konnichiwa", data: d))
        XCTAssertTrue(TypingExerciseView.isAcceptable(input: "  コンニチハ ", data: d))
    }

    func testWrongInput_Rejected() {
        XCTAssertFalse(TypingExerciseView.isAcceptable(input: "sayonara", data: data(answer: "konnichiwa")))
    }

    func testEmptyInput_Rejected() {
        XCTAssertFalse(TypingExerciseView.isAcceptable(input: "", data: data(answer: "konnichiwa")))
        XCTAssertFalse(TypingExerciseView.isAcceptable(input: "    ", data: data(answer: "konnichiwa")))
    }
}
