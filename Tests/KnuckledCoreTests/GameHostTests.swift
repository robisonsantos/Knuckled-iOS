import XCTest
@testable import KnuckledCore

final class GameHostTests: XCTestCase {

    private func host(link: FakeGameLink, first: PlayerId, body: (GameHost) -> Void) {
        let gh = GameHost(
            link: link,
            hostName: "Host",
            rollValue: { 4 },
            rollDelayMs: 0,
            firstPlayer: { first },
            onState: { _ in }
        )
        body(gh)
    }

    private func lastStateSent(_ link: FakeGameLink) -> GameState {
        link.sent.reversed().compactMap { MessageCodec.decodeState($0) }.first!
    }

    func testClientNameTriggersResetWithBothPlayersAndChosenFirstPlayer() {
        let link = FakeGameLink()
        host(link: link, first: .CLIENT) { gameHost in
            gameHost.connect()
            link.receive(MessageCodec.encodeName("  Bob  "))
            let state = self.lastStateSent(link)
            XCTAssertEqual(state.clientName, "Bob")
            XCTAssertEqual(state.hostName, "Host")
            XCTAssertEqual(state.currentTurn, .CLIENT)
            XCTAssertEqual(state.status, .IN_PROGRESS)
        }
    }

    func testHostRollRollsAndGoesToAwaitingPlacementOnTheHost() {
        let link = FakeGameLink()
        host(link: link, first: .HOST) { gameHost in
            gameHost.connect()
            link.receive(MessageCodec.encodeName("Bob"))
            gameHost.hostRoll()
            let state = self.lastStateSent(link)
            XCTAssertEqual(state.phase, .AWAITING_PLACEMENT)
            XCTAssertEqual(state.lastRoll, 4)
            XCTAssertEqual(state.currentTurn, .HOST)
        }
    }

    func testHostPlacePlacesTheDieAndHandsTheTurnToTheClient() {
        let link = FakeGameLink()
        host(link: link, first: .HOST) { gameHost in
            gameHost.connect()
            link.receive(MessageCodec.encodeName("Bob"))
            gameHost.hostRoll()
            gameHost.hostPlace(2)
            let state = self.lastStateSent(link)
            XCTAssertEqual(state.currentTurn, .CLIENT)
            XCTAssertEqual(state.phase, .IDLE)
            XCTAssertEqual(state.grid[.HOST]![2], [4])
        }
    }

    func testClientRollAndPlaceMessagesDriveTheGame() {
        let link = FakeGameLink()
        host(link: link, first: .HOST) { gameHost in
            gameHost.connect()
            link.receive(MessageCodec.encodeName("Bob"))
            gameHost.hostRoll()
            gameHost.hostPlace(0)
            link.receive(MessageCodec.encodeRoll())
            let rolled = self.lastStateSent(link)
            XCTAssertEqual(rolled.phase, .AWAITING_PLACEMENT)
            XCTAssertEqual(rolled.currentTurn, .CLIENT)
            link.receive(MessageCodec.encodePlace(1))
            let state = self.lastStateSent(link)
            XCTAssertEqual(state.currentTurn, .HOST)
            XCTAssertEqual(state.grid[.CLIENT]![1], [4])
        }
    }

    func testInvalidMessagesAreIgnored() {
        let link = FakeGameLink()
        host(link: link, first: .CLIENT) { gameHost in
            gameHost.connect()
            link.receive(MessageCodec.encodeName("Bob"))
            gameHost.hostRoll()
            XCTAssertEqual(link.sent.count { MessageCodec.decodeState($0) != nil }, 1)
            link.receive(MessageCodec.encodeRoll())
            XCTAssertEqual(self.lastStateSent(link).currentTurn, .CLIENT)
            link.receive("GARBAGE")
            link.receive("PLACE:9")
            XCTAssertEqual(link.sent.count { MessageCodec.decodeState($0) != nil }, 3)
        }
    }

    func testRestartKeepsNamesAndTheSameFirstPlayerButFreshBoards() {
        // Drive a full game to a terminal state, then restart.
        let link = FakeGameLink()
        var finished: GameState? = nil
        var counter = 0
        let gh = GameHost(
            link: link,
            hostName: "Host",
            rollValue: { counter % 6 + 1 ; counter += 1; return counter % 6 + 1 },
            rollDelayMs: 0,
            firstPlayer: { .HOST },
            onState: { finished = $0 }
        )
        gh.connect()
        link.receive(MessageCodec.encodeName("Bob"))
        var guardCount = 0
        while finished?.status == .IN_PROGRESS && guardCount < 300 {
            let s = finished ?? self.lastStateSent(link)
            if KnucklebonesRules.canRoll(s, s.currentTurn) {
                if s.currentTurn == .HOST { gh.hostRoll() } else { link.receive(MessageCodec.encodeRoll()) }
            } else {
                let grid = s.grid[s.currentTurn]!
                let col = grid.indices.first { !KnucklebonesRules.columnFull(grid, $0) }!
                if s.currentTurn == .HOST { gh.hostPlace(col) } else { link.receive(MessageCodec.encodePlace(col)) }
            }
            guardCount += 1
        }
        XCTAssertNotNil(finished)
        XCTAssertNotEqual(finished!.status, .IN_PROGRESS)

        gh.restart()
        let restarted = finished!
        XCTAssertEqual(restarted.status, .IN_PROGRESS)
        XCTAssertEqual(restarted.hostName, "Host")
        XCTAssertEqual(restarted.clientName, "Bob")
        XCTAssertTrue(restarted.grid.values.allSatisfy { grid in grid.allSatisfy { $0.isEmpty } })
    }
}
