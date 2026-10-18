import XCTest
@testable import YuE2Studio

@MainActor
final class CreateSongViewModelTests: XCTestCase {
    private func makeVM() -> (CreateSongViewModel, StubYuE2Service, HistoryStore) {
        let history = HistoryStore(directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-\(UUID().uuidString)"))
        let stub = StubYuE2Service()
        return (CreateSongViewModel(clientProvider: { stub }, history: history), stub, history)
    }

    func testValidationBlocksEmptyStyleOrLyrics() {
        let (vm, _, _) = makeVM()
        vm.style = ""
        vm.lyrics = "词"
        XCTAssertEqual(vm.validationMessage(), "请填写风格提示（Style prompt）")
        vm.style = "风格"
        vm.lyrics = ""
        XCTAssertEqual(vm.validationMessage(), "请填写歌词（Lyrics）")
    }

    func testValidationABCRequiresXHeader() {
        let (vm, _, _) = makeVM()
        vm.style = "风格"; vm.lyrics = "词"; vm.cot = .full; vm.abc = "K:C\n"
        XCTAssertEqual(vm.validationMessage(), "ABC 乐谱需要以 X: 开头（YuE2 生成的乐谱可直接粘贴）")
    }

    func testValidationSeedAndGuidance() {
        let (vm, _, _) = makeVM()
        vm.style = "风格"; vm.lyrics = "词"
        vm.seedText = "abc"
        XCTAssertEqual(vm.validationMessage(), "随机种子只能是整数")
        vm.seedText = "42"
        vm.guidanceText = "-1"
        XCTAssertEqual(vm.validationMessage(), "Guidance 只能是大于 0 的数字")
        vm.guidanceText = "1.2"
        XCTAssertNil(vm.validationMessage())
    }

    func testMakeRequestTrimsAndKeepsABC() {
        let (vm, _, _) = makeVM()
        vm.style = " 风格 "; vm.lyrics = " 词 "; vm.cot = .melody; vm.abc = " X:1 "
        let req = vm.makeRequest()
        XCTAssertEqual(req?.style, "风格")
        XCTAssertEqual(req?.abc, "X:1")
        XCTAssertEqual(req?.cot, .melody)
    }

    func testSubmitSuccessWritesHistoryAndCallsOnCreated() async {
        let (vm, stub, history) = makeVM()
        var created: String?
        vm.onCreated = { created = $0 }
        vm.style = "city pop"; vm.lyrics = "[Verse]"
        vm.submit()
        // submit 是异步 Task，等两个 runloop 让 stub 同步返回
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(stub.generateCalls.count, 1)
        XCTAssertEqual(created, "job-1")
        XCTAssertEqual(history.all().first?.lastStatus, .queued)
        XCTAssertTrue(vm.style.isEmpty)  // 提交后清空
    }

    func testSubmitFailureSetsMessage() async {
        let (vm, stub, _) = makeVM()
        stub.generateResult = .failure(APIError.http(status: 400, message: "风格或歌词不能为空"))
        vm.style = "s"; vm.lyrics = "l"
        vm.submit()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.errorMessage, "风格或歌词不能为空")
        XCTAssertFalse(vm.isSubmitting)
    }
}
