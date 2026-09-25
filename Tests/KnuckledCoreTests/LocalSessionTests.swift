import XCTest
@testable import KnuckledCore

final class LocalSessionTests: XCTestCase {

    func testHostRunsCpuToTerminalStateOverInMemoryLink() {
        let (humanLink, cpuLink) = InMemoryLinkPair.make()
        runCpuClient(cpuLink, preRollDelayMs: 0, thinkDelay: { 0 })

        let counter = Counter()
        let gh = GameHost(
            link: humanLink,
            hostName: "Human",
            rollValue: { counter.increment(); return (counter.value % 6) + 1 },
            rollDelayMs: 0,
            firstPlayer: { .CLIENT }
        )
        gh.connect()

        // Wait for the CPU's NAME handshake (the host starts from a placeholder state).
        var handshakeGuard = 0
        while gh.state.clientName == "?" && handshakeGuard < 200 {
            Thread.sleep(forTimeInterval: 0.02)
            handshakeGuard += 1
        }
        XCTAssertNotEqual(gh.state.clientName, "?", "handshake should complete")

        var guardCount = 0
        while gh.state.status == .IN_PROGRESS && guardCount < 3000 {
            let s = gh.state
            if KnucklebonesRules.canRoll(s, .HOST) {
                gh.hostRoll()
            } else if s.phase == .AWAITING_PLACEMENT && s.currentTurn == .HOST {
                gh.hostPlace(FakeGamePeer.firstOpenColumn(s.grid[.HOST]!))
            } else {
                Thread.sleep(forTimeInterval: 0.02)
            }
            guardCount += 1
        }
        XCTAssertNotEqual(gh.state.status, .IN_PROGRESS, "game should finish (steps=\(guardCount))")
        XCTAssertEqual(gh.state.clientName, CpuPlayer.name)
        XCTAssertEqual(gh.state.grid[.CLIENT]!.flatMap { $0 }.count, 9)
    }

    func testFakeHostServesAClientOverInMemoryLink() {
        let (clientLink, hostLink) = InMemoryLinkPair.make()
        let host = runFakeHost(hostLink)
        var forwarded = 0
        var lastState: GameState? = nil
        let stateLock = NSLock()
        func setLast(_ s: GameState) { stateLock.lock(); lastState = s; stateLock.unlock() }
        func getLast() -> GameState? { stateLock.lock(); defer { stateLock.unlock() }; return lastState }
        let link = clientLink
        link.onLine = { line in
            guard let state = MessageCodec.decodeState(line) else { return }
            setLast(state)
            if KnucklebonesRules.canRoll(state, .CLIENT) {
                try? link.send(MessageCodec.encodeRoll())
            } else if state.phase == .AWAITING_PLACEMENT && state.currentTurn == .CLIENT {
                if let grid = state.grid[.CLIENT] {
                    try? link.send(MessageCodec.encodePlace(FakeGamePeer.firstOpenColumn(grid)))
                }
            }
            _ = host
            _ = forwarded
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
