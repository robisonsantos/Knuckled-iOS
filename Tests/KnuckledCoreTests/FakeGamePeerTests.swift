import XCTest
@testable import KnuckledCore

final class FakeGamePeerTests: XCTestCase {

    func testFakeClientPlaysAFullSessionToADrawOrFinish() {
        let hostLink = FakeGameLink()
        var counter = Counter()
        let gh = GameHost(
            link: hostLink,
            hostName: FakeGamePeer.hostName,
            rollValue: { counter.increment(); return (counter.value % 6) + 1 },
            rollDelayMs: 0,
            firstPlayer: { .HOST },
            onState: { _ in }
        )
        gh.connect()

        var clientLines: [String] = []
        var forwarded = 0
        var botLink: ProxyLink!
        func pumpToBot() {
            while forwarded < hostLink.sent.count {
                let hostLine = hostLink.sent[forwarded]
                forwarded += 1
                if MessageCodec.decodeState(hostLine) != nil {
                    botLink.onLine?(hostLine)
                }
            }
        }
        botLink = ProxyLink(
            receiveToHost: { line in
                clientLines.append(line)
                hostLink.receive(line)
                pumpToBot()
            },
            onClose: { }
        )
        runFakeClient(botLink)

        var guardCount = 0
        while gh.state.status == .IN_PROGRESS && guardCount < 900 {
            let s = gh.state
            if KnucklebonesRules.canRoll(s, .HOST) {
                gh.hostRoll()
                pumpToBot()
            } else if s.phase == .AWAITING_PLACEMENT && s.currentTurn == .HOST {
                let col = FakeGamePeer.firstOpenColumn(s.grid[.HOST]!)
                gh.hostPlace(col)
                pumpToBot()
            } else {
                Thread.sleep(forTimeInterval: 0.02)
                pumpToBot()
            }
            guardCount += 1
        }
        XCTAssertNotEqual(gh.state.status, .IN_PROGRESS, "game should finish (steps=\(guardCount))")
        if gh.state.status == .FINISHED { XCTAssertNotNil(gh.state.winner) }
        XCTAssertEqual(gh.state.clientName, FakeGamePeer.name)
        XCTAssertFalse(clientLines.isEmpty)
    }
}
