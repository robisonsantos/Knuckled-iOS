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
        let pumpLock = NSLock()
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
                pumpLock.lock()
                clientLines.append(line)
                pumpLock.unlock()
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

    func testRunFakeHostBotPlaysItsTurnsToTerminalState() {
        let (clientLink, hostLink) = InMemoryLinkPair.make()
        let host = runFakeHost(hostLink)
        var lastState: GameState? = nil
        let stateLock = NSLock()
        func setLast(_ s: GameState) { stateLock.lock(); lastState = s; stateLock.unlock() }
        func getLast() -> GameState? { stateLock.lock(); defer { stateLock.unlock() }; return lastState }
        clientLink.onLine = { line in
            guard let state = MessageCodec.decodeState(line) else { return }
            setLast(state)
            if KnucklebonesRules.canRoll(state, .CLIENT) {
                try? clientLink.send(MessageCodec.encodeRoll())
            } else if state.phase == .AWAITING_PLACEMENT && state.currentTurn == .CLIENT {
                if let grid = state.grid[.CLIENT] {
                    try? clientLink.send(MessageCodec.encodePlace(FakeGamePeer.firstOpenColumn(grid)))
                }
            }
            _ = host // retain for the session duration
        }
        try? clientLink.send(MessageCodec.encodeName("Human"))
        var guardCount = 0
        while (getLast()?.status ?? .IN_PROGRESS) == .IN_PROGRESS && guardCount < 3000 {
            Thread.sleep(forTimeInterval: 0.02)
            guardCount += 1
        }
        let final = getLast()
        XCTAssertNotNil(final)
        XCTAssertNotEqual(final!.status, .IN_PROGRESS, "game should finish (steps=\(guardCount))")
    }
}
