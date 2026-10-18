import XCTest
@testable import YuE2Studio

@MainActor
final class JobDetailViewModelTests: XCTestCase {
    private func makeVM(jobId: String = "job-1") -> (JobDetailViewModel, StubYuE2Service, HistoryStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("detail-\(UUID().uuidString)")
        let history = HistoryStore(directoryURL: dir)
        let stub = StubYuE2Service()
        return (JobDetailViewModel(jobId: jobId, clientProvider: { stub }, history: history), stub, history)
    }

    func testLoadPopulatesDetail() async {
        let (vm, stub, _) = makeVM()
        stub.jobResultByID["job-1"] = .success(Fixtures.detail())
        await vm.load()
        XCTAssertEqual(vm.detail?.status, .running)
        XCTAssertTrue(vm.isActive)
        XCTAssertNil(vm.errorMessage)
    }

    func testLoadSuccessWritesHistoryAndScore() async {
        let (vm, stub, history) = makeVM()
        stub.jobResultByID["job-1"] = .success(Fixtures.doneDetail())
        history.addOrUpdate(HistoryEntry(id: "job-1", title: "t", style: "s", cot: .full,
                                         createdAt: Date(), lastStatus: .running))
        await vm.load()
        XCTAssertEqual(vm.detail?.result?.audioSeconds ?? 0, 182.4, accuracy: 0.01)
        XCTAssertFalse(vm.isActive)
        XCTAssertEqual(history.all()[0].lastStatus, .succeeded)
    }

    func testLoad404MarksHistoryMissing() async {
        let (vm, _, history) = makeVM()
        history.addOrUpdate(HistoryEntry(id: "job-1", title: "t", style: "s", cot: .full,
                                         createdAt: Date(), lastStatus: .running))
        await vm.load()  // stub 默认对未编排的 id 抛 404
        XCTAssertTrue(history.all()[0].missingOnServer)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.detail)
    }

    func testCancelJobViaService() async {
        let (vm, stub, _) = makeVM()
        stub.jobResultByID["job-1"] = .success(Fixtures.detail())
        vm.cancelJob()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(stub.cancelCalls, ["job-1"])
        XCTAssertEqual(vm.detail?.status, .running)
    }

    func testMakeRetryRequestFromParams() async {
        let (vm, stub, _) = makeVM()
        stub.jobResultByID["job-1"] = .success(Fixtures.doneDetail())
        await vm.load()
        let req = vm.makeRetryRequest()
        XCTAssertEqual(req?.style, "English, warm piano pop")
        XCTAssertEqual(req?.lyrics, "[Verse]\nline one")
        XCTAssertEqual(req?.cot, .full)
        XCTAssertEqual(req?.seed, 42)
    }
}
