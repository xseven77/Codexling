import CZSTD
import XCTest
@testable import Codexling

final class DSHActivityServiceTests: XCTestCase {
    private func makeService() -> DSHActivityService {
        DSHActivityService(sessionsRoot: FileManager.default.temporaryDirectory)
    }

    func testParseEventsAndStateMapping() {
        let service = makeService()
        let events = service.parseEvents(from: """
        {"type":"session","time":1786812701838}
        {"type":"turn/start","time":1786812713323,"data":{"turn":1}}
        {"type":"user/message","time":1786812713343,"data":{"content":[{"type":"text","text":"hello"}]}}
        {"type":"session/title","time":1786812713344,"data":{"title":"My Task"}}
        {"type":"tool/call","time":1786812720000,"data":{"name":"bash"}}
        """)

        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events.map(\.type), ["session", "turn/start", "user/message", "session/title", "tool/call"])
        XCTAssertEqual(service.state(for: events), .executing)
        XCTAssertEqual(service.sessionTitle(from: events, fallback: "x"), "My Task")
    }

    func testStateIdleAfterTurnEnd() {
        let service = makeService()
        let events = service.parseEvents(from: """
        {"type":"turn/start","time":1}
        {"type":"assistant/message","time":2,"data":{"content":[]}}
        {"type":"turn/end","time":3}
        """)
        XCTAssertEqual(service.state(for: events), .idle)
    }

    func testStateThinkingAfterUserMessage() {
        let service = makeService()
        let events = service.parseEvents(from: """
        {"type":"user/message","time":1,"data":{"content":[{"type":"text","text":"hi"}]}}
        """)
        XCTAssertEqual(service.state(for: events), .thinking)
    }

    func testStateReviewingAfterAssistantMessage() {
        let service = makeService()
        let events = service.parseEvents(from: """
        {"type":"assistant/message","time":1,"data":{"content":[]}}
        """)
        XCTAssertEqual(service.state(for: events), .reviewing)
    }

    func testStateWaitingForUserAfterApprovalAsked() {
        let service = makeService()
        let events = service.parseEvents(from: """
        {"type":"tool/call","time":1,"data":{"name":"bash"}}
        {"type":"approval/asked","time":2,"data":{"toolName":"bash","reason":"escalate sandbox"}}
        """)
        XCTAssertEqual(service.state(for: events), .waitingForUser)
    }

    func testStateThinkingAfterApprovalDecided() {
        let service = makeService()
        let events = service.parseEvents(from: """
        {"type":"approval/asked","time":1}
        {"type":"approval/decided","time":2,"data":{"outcome":"allowed-once"}}
        """)
        XCTAssertEqual(service.state(for: events), .thinking)
    }

    func testMetadataEventsDoNotOverrideState() {
        let service = makeService()
        // 会话结束后追加的元数据事件不应把状态从 idle 改成别的，也不该误判为活跃。
        let events = service.parseEvents(from: """
        {"type":"tool/call","time":1}
        {"type":"tool/result","time":2}
        {"type":"turn/end","time":3}
        {"type":"goal/change","time":4,"data":{"operation":"complete"}}
        {"type":"compaction/prune","time":5}
        {"type":"session/end-seed","time":6,"data":{}}
        """)
        XCTAssertEqual(service.state(for: events), .idle)
    }

    func testCommandRunMapsToExecuting() {
        let service = makeService()
        let events = service.parseEvents(from: """
        {"type":"command/run","time":1,"data":{}}
        """)
        XCTAssertEqual(service.state(for: events), .executing)
    }

    func testSessionTitleFallsBackToFirstMessage() {
        let service = makeService()
        let events = service.parseEvents(from: """
        {"type":"user/message","time":1,"data":{"content":[{"type":"text","text":"帮我修一下这个 bug"}]}}
        {"type":"tool/call","time":2}
        """)
        let title = service.sessionTitle(from: events, fallback: "fallback")
        XCTAssertEqual(title, "帮我修一下这个 bug")
    }

    func testDecompressedTailRoundTrip() {
        let service = makeService()
        let events = (1...10).map { "{\"type\":\"event\",\"n\":\($0)}" }
        var compressed = Data()
        for event in events {
            compressed.append(zstdCompress(Data((event + "\n").utf8)))
        }

        let tail = service.decompressedTail(from: compressed, maxFrames: 3)
        let text = String(data: tail ?? Data(), encoding: .utf8) ?? ""

        // 用带 `}` 的完整键值避免 "n":1 误匹配 "n":10。
        XCTAssertTrue(text.contains("\"n\":8}"))
        XCTAssertTrue(text.contains("\"n\":9}"))
        XCTAssertTrue(text.contains("\"n\":10}"))
        XCTAssertFalse(text.contains("\"n\":1}"))
        XCTAssertFalse(text.contains("\"n\":7}"))
    }

    func testDecompressedHeadRoundTrip() {
        let service = makeService()
        let events = (1...10).map { "{\"type\":\"event\",\"n\":\($0)}" }
        var compressed = Data()
        for event in events {
            compressed.append(zstdCompress(Data((event + "\n").utf8)))
        }

        let head = service.decompressedHead(from: compressed, maxFrames: 3)
        let text = String(data: head ?? Data(), encoding: .utf8) ?? ""

        XCTAssertTrue(text.contains("\"n\":1}"))
        XCTAssertTrue(text.contains("\"n\":2}"))
        XCTAssertTrue(text.contains("\"n\":3}"))
        XCTAssertFalse(text.contains("\"n\":4}"))
        XCTAssertFalse(text.contains("\"n\":10}"))
    }

    private func zstdCompress(_ data: Data) -> Data {
        let bound = ZSTD_compressBound(data.count)
        var dst = Data(count: Int(bound))
        let written = data.withUnsafeBytes { src in
            dst.withUnsafeMutableBytes { dstBuf in
                Int(ZSTD_compress(
                    dstBuf.baseAddress!,
                    Int(bound),
                    src.baseAddress!,
                    data.count,
                    1
                ))
            }
        }
        return dst.prefix(written)
    }
}
