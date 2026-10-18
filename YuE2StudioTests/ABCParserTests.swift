import XCTest
@testable import YuE2Studio

final class ABCParserTests: XCTestCase {
    func testParsesTitleAndSections() {
        let abc = """
        X:1
        T:Neon Nights
        C:YuE2
        M:4/4
        L:1/8
        K:C
        w:[Verse] Neon fades along the lane
        [Chorus]
        w:Let the day come into view
        """
        let parsed = ABCParser(abc: abc)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.title, "Neon Nights")
        XCTAssertEqual(parsed?.sections, ["Verse", "Chorus"])
        XCTAssertEqual(parsed?.isValid, true)
        XCTAssertEqual(parsed?.displayTitle, "Neon Nights")
        XCTAssertEqual(parsed?.sectionSummary, "Verse · Chorus")
    }

    func testFallsBackWhenNoTitle() {
        let abc = "X:1\nK:C\nCDEF"
        XCTAssertEqual(ABCParser(abc: abc)?.displayTitle, "未命名乐谱")
    }

    func testNilAndEmpty() {
        XCTAssertNil(ABCParser(abc: nil))
        XCTAssertNil(ABCParser(abc: "   "))
    }
}
