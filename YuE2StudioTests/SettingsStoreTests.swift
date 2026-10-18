import XCTest
@testable import YuE2Studio

final class SettingsStoreTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "settings-tests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultsFull() {
        let s = SettingsStore(defaults: suite)
        XCTAssertEqual(s.defaultCot, .full)
        XCTAssertFalse(s.onboardingDone)
        XCTAssertFalse(s.isServerConfigured)
    }

    func testPersistRoundTrip() {
        let s = SettingsStore(defaults: suite)
        s.serverAddress = "https://yue2.example.com"
        s.apiKey = "k"
        s.defaultCot = .melody
        s.onboardingDone = true

        let s2 = SettingsStore(defaults: suite)
        XCTAssertEqual(s2.serverAddress, "https://yue2.example.com")
        XCTAssertEqual(s2.apiKey, "k")
        XCTAssertEqual(s2.defaultCot, .melody)
        XCTAssertTrue(s2.onboardingDone)
        XCTAssertTrue(s2.isServerConfigured)
        XCTAssertEqual(s2.normalizedServerURL?.absoluteString, "https://yue2.example.com")
    }

    func testMakeClientCarriesBaseURLAndKey() {
        let s = SettingsStore(defaults: suite)
        s.serverAddress = "http://192.168.1.5:8420/"
        s.apiKey = "secret"
        let c = s.makeClient()
        XCTAssertEqual(c.baseURL.absoluteString, "http://192.168.1.5:8420")
        XCTAssertEqual(c.apiKey, "secret")
        XCTAssertEqual(c.authHeaders(), ["X-API-Key": "secret"])
    }

    func testInvalidAddressNotConfigured() {
        let s = SettingsStore(defaults: suite)
        s.serverAddress = "not a url"
        XCTAssertFalse(s.isServerConfigured)
    }
}
