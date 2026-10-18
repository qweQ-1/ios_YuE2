import XCTest
@testable import YuE2Studio

final class ScoreRendererTests: XCTestCase {
    func testHTMLContainsEscapedABCAndScript() {
        let abc = "X:1\nT:Danger \"quoted\" </script>\nK:C"
        let html = ScoreRenderer.html(forScore: abc)
        XCTAssertTrue(html.contains(ScoreRenderer.jsFileName))
        XCTAssertTrue(html.contains("renderAbc"))
        // 引号与 </script> 必须被转义，否则会截断/注入
        XCTAssertFalse(html.contains("</script>\nK:C"))  // 原文不会被插入
        XCTAssertTrue(html.contains("\\u003C/script\\u003E"))
        XCTAssertTrue(html.contains("\\\""))
    }

    func testJsStringLiteral() {
        XCTAssertEqual(ScoreRenderer.jsStringLiteral("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"")
    }

    func testRendersPlainChineseLyrics() {
        let html = ScoreRenderer.html(forScore: "X:1\nT:测试\nK:C")
        XCTAssertTrue(html.contains("测试"))
    }
}
