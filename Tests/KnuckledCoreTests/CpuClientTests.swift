import XCTest
@testable import KnuckledCore

final class CpuClientTests: XCTestCase {

    private func playFullGame(firstPlayer: PlayerId) -> GameState {
        let hostLink = FakeGameLink()
        let counter = Counter()
        let gh = GameHost(
            link: hostLink,
            hostName: "Human",
            rollValue: { counter.increment(); return (counter.value % 6) + 1 },
            rollDelayMs: 0,
            firstPlayer: { firstPlayer },
            onState: { _ in }
        )
        gh.connect()

        let pumpLock = NSLock()
        var forwarded = 0
        var botLink: ProxyLink!
        func pumpToBot() {
            pumpLock.lock()
            defer { pumpLock.unlock() }
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
                hostLink.receive(line)
                pumpToBot()
            },
            onClose: { }
        )
        runCpuClient(botLink, preRollDelayMs: 0, thinkDelay: { 0 })
        pumpToBot()

        var guardCount = 0
        while gh.state.status == .IN_PROGRESS && guardCount < 2000 {
            let s = gh.state
            if KnucklebonesRules.canRoll(s, .HOST) {
                gh.hostRoll()
                pumpToBot()
            } else if s.phase == .AWAITING_PLACEMENT && s.currentTurn == .HOST {
                gh.hostPlace(FakeGamePeer.firstOpenColumn(s.grid[.HOST]!))
                pumpToBot()
            } else {
                Thread.sleep(forTimeInterval: 0.02)
                pumpToBot()
            }
            guardCount += 1
        }
        return gh.state
    }

    func testCpuPlaysAFullSessionAndFillsItsOwnBoard() {
        let state = playFullGame(firstPlayer: .CLIENT)
        XCTAssertTrue(state.status == .FINISHED || state.status == .DRAW, "game should finish (state=\(state))")
        if state.status == .FINISHED { XCTAssertNotNil(state.winner) }
        XCTAssertEqual(state.clientName, CpuPlayer.name)
        XCTAssertEqual(state.grid[.CLIENT]!.flatMap { $0 }.count, 9)
    }

    func testCpuKeepsPlayingAfterARestart() {
        let hostLink = FakeGameLink()
        let counter = Counter()
        let gh = GameHost(
            link: hostLink,
            hostName: "Human",
            rollValue: { counter.increment(); return (counter.value % 6) + 1 },
            rollDelayMs: 0,
            firstPlayer: { .CLIENT },
            onState: { _ in }
        )
        gh.connect()

        let pumpLock = NSLock()
        var forwarded = 0
        var botLink: ProxyLink!
        func pumpToBot() {
            pumpLock.lock()
            defer { pumpLock.unlock() }
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
                hostLink.receive(line)
                pumpToBot()
            },
            onClose: { }
        )
        runCpuClient(botLink, preRollDelayMs: 0, thinkDelay: { 0 })
        pumpToBot()

        func playWhileInProgress() {
            var guardCount = 0
            while gh.state.status == .IN_PROGRESS && guardCount < 2000 {
                let s = gh.state
                if KnucklebonesRules.canRoll(s, .HOST) {
                    gh.hostRoll()
                    pumpToBot()
                } else if s.phase == .AWAITING_PLACEMENT && s.currentTurn == .HOST {
                    gh.hostPlace(FakeGamePeer.firstOpenColumn(s.grid[.HOST]!))
                    pumpToBot()
                } else {
                    Thread.sleep(forTimeInterval: 0.02)
                    pumpToBot()
                }
                guardCount += 1
            }
        }

        playWhileInProgress()
        XCTAssertNotEqual(gh.state.status, .IN_PROGRESS, "first game should finish")
        gh.restart()
        pumpToBot()
        XCTAssertEqual(gh.state.status, .IN_PROGRESS, "restart should be in progress")
        XCTAssertEqual(gh.state.clientName, CpuPlayer.name)
        playWhileInProgress()
        XCTAssertNotEqual(gh.state.status, .IN_PROGRESS, "second game should finish")
        XCTAssertEqual(gh.state.grid[.CLIENT]!.flatMap { $0 }.count, 9)
    }
}
