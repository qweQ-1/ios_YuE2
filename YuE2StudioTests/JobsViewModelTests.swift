import XCTest
@testable import YuE2Studio

@MainActor
final class JobsViewModelTests: XCTestCase {
    private func makeVM() -> (JobsViewModel, StubYuE2Service, HistoryStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-\(UUID().uuidString)")
        let history = HistoryStore(directoryURL: dir)
        let stub = StubYuE2Service()
        return (JobsViewModel(clientProvider: { stub }, history: history), stub, history)
    }

    func testRefreshMergesServerItemsAndHistory() async {
        let (vm, stub, history) = makeVM()
        stub.jobsResult = .success(JobListResponse(items: [
            Fixtures.summary(id: "s1", status: .succeeded),
            Fixtures.summary(id: "s2", status: .running),
        ], total: 2))
        history.addOrUpdate(HistoryEntry(id: "s1", title: "旧", style: "s", cot: .full,
                                         createdAt: Date(), lastStatus: .running))
        history.addOrUpdate(HistoryEntry(id: "old-missing", title: "被淘汰", style: "s", cot: .off,
                                         createdAt: Date().addingTimeInterval(-50), lastStatus: .succeeded))

        await vm.refresh()
        XCTAssertEqual(vm.items.count, 3)
        XCTAssertTrue(vm.hasActive)

        // 服务器条目：id、状态以服务器为准，并回写历史
        let s1 = vm.items.first { $0.id == "s1" }!
        XCTAssertEqual(s1.status, .succeeded)
        XCTAssertFalse(s1.missing)
        XCTAssertEqual(history.all().first { $0.id == "s1" }?.lastStatus, .succeeded)

        // 本地独有条目标记为已失效，排在后面
        let ghost = vm.items.first { $0.id == "old-missing" }!
        XCTAssertTrue(ghost.missing)
        XCTAssertEqual(vm.items.last?.id, "old-missing")
    }

    func testRefreshErrorSetsMessage() async {
        let (vm, stub, _) = makeVM()
        stub.jobsResult = .failure(APIError.network("notConnectedToInternet"))
        await vm.refresh()
        XCTAssertEqual(vm.errorMessage, "连接服务器失败：notConnectedToInternet")
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertFalse(vm.hasActive)
    }

    func testCancelCallsService() async {
        let (vm, stub, _) = makeVM()
        stub.jobsResult = .success(JobListResponse(items: [Fixtures.summary(id: "c1", status: .running)], total: 1))
        vm.cancel(id: "c1")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(stub.cancelCalls, ["c1"])
    }
}
