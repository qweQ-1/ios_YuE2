import XCTest
@testable import YuE2Studio

final class HistoryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testAddAndListSorted() {
        let store = HistoryStore(directoryURL: dir)
        let now = Date()
        store.addOrUpdate(HistoryEntry(id: "old", title: "老", style: "s", cot: .full,
                                       createdAt: now.addingTimeInterval(-100), lastStatus: .succeeded))
        store.addOrUpdate(HistoryEntry(id: "new", title: "新", style: "s", cot: .off,
                                       createdAt: now, lastStatus: .running))
        XCTAssertEqual(store.all().map(\.id), ["new", "old"])
    }

    func testAddOrUpdateMergesStatus() {
        let store = HistoryStore(directoryURL: dir)
        store.addOrUpdate(HistoryEntry(id: "a", title: "t", style: "s", cot: .full,
                                       createdAt: Date(), lastStatus: .queued))
        store.addOrUpdate(HistoryEntry(id: "a", title: "t", style: "s", cot: .full,
                                       createdAt: Date(), lastStatus: .succeeded, audioSeconds: 12))
        let all = store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].lastStatus, .succeeded)
        XCTAssertEqual(all[0].audioSeconds, 12)
    }

    func testMarkStatusAndMissing() {
        let store = HistoryStore(directoryURL: dir)
        store.addOrUpdate(HistoryEntry(id: "a", title: "t", style: "s", cot: .full,
                                       createdAt: Date(), lastStatus: .running))
        store.markStatus(id: "a", status: .failed, missing: true)
        XCTAssertEqual(store.all()[0].lastStatus, .failed)
        XCTAssertTrue(store.all()[0].missingOnServer)
    }

    func testPersistenceAcrossInstances() {
        let store = HistoryStore(directoryURL: dir)
        store.addOrUpdate(HistoryEntry(id: "p", title: "t", style: "s", cot: .melody,
                                       createdAt: Date(), lastStatus: .succeeded))
        let reopened = HistoryStore(directoryURL: dir)
        XCTAssertEqual(reopened.all().first?.id, "p")
    }

    func testRemoveAndClear() {
        let store = HistoryStore(directoryURL: dir)
        store.addOrUpdate(HistoryEntry(id: "a", title: "t", style: "s", cot: .full, createdAt: Date(), lastStatus: nil))
        store.remove(id: "a")
        XCTAssertTrue(store.all().isEmpty)
        store.addOrUpdate(HistoryEntry(id: "b", title: "t", style: "s", cot: .full, createdAt: Date(), lastStatus: nil))
        store.clear()
        XCTAssertTrue(store.all().isEmpty)
    }
}
