import XCTest
@testable import YuE2Studio

final class ServerURLTests: XCTestCase {
    func testAutoPrefixHTTPS() {
        XCTAssertEqual(ServerURL.normalize("yue2.example.com")?.absoluteString, "https://yue2.example.com")
    }

    func testKeepsHTTPSAndPort() {
        XCTAssertEqual(ServerURL.normalize("https://1.2.3.4:8420")?.absoluteString, "https://1.2.3.4:8420")
    }

    func testKeepsHTTPForLAN() {
        XCTAssertEqual(ServerURL.normalize("http://192.168.1.10:8420/")?.absoluteString, "http://192.168.1.10:8420")
    }

    func testStripsTrailingSlashes() {
        XCTAssertEqual(ServerURL.normalize("https://a.com///")?.absoluteString, "https://a.com")
    }

    func testRejectsGarbage() {
        XCTAssertNil(ServerURL.normalize("   "))
        XCTAssertNil(ServerURL.normalize("ftp://a.com"))
        XCTAssertNil(ServerURL.normalize("https://"))
    }

    func testValidationMessage() {
        XCTAssertNil(ServerURL.validationMessage("yue2.example.com"))
        XCTAssertNotNil(ServerURL.validationMessage(""))
        XCTAssertNotNil(ServerURL.validationMessage("ftp://x"))
    }
}
