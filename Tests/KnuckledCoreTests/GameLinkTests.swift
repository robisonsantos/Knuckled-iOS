import XCTest
@testable import KnuckledCore

final class GameLinkTests: XCTestCase {

    func testSendDeliversToPeerOnLine() {
        let input = Channel()
        let received = ReceivedList()
        let link = GameLinkCore(input: input, output: Channel())
        link.onLine = { received.append($0) }

        input.write(Data("roll 5\n".utf8))
        `await`(received.values == ["roll 5"])
        XCTAssertEqual(received.values, ["roll 5"])
    }

    func testOnLineReceivesUnicodeLine() {
        let input = Channel()
        let received = ReceivedList()
        let link = GameLinkCore(input: input, output: Channel())
        link.onLine = { received.append($0) }
        Protocol.writeLine("héllo 世界", to: input)
        `await`(received.values.count == 1)
        XCTAssertEqual(received.values, ["héllo 世界"])
    }

    func testBidirectionalMessagesRoundTrip() {
        let aToB = Channel()
        let bToA = Channel()
        let a = GameLinkCore(input: bToA, output: aToB)
        let b = GameLinkCore(input: aToB, output: bToA)
        let aReceived = ReceivedList()
        let bReceived = ReceivedList()
        a.onLine = { aReceived.append($0) }
        b.onLine = { bReceived.append($0) }

        for i in 1...50 {
            try! a.send("a->b \(i)")
            try! b.send("b->a \(i)")
        }
        `await`(bReceived.values.count == 50)
        `await`(aReceived.values.count == 50)
        XCTAssertEqual(aReceived.values, (1...50).map { "b->a \($0)" })
        XCTAssertEqual(bReceived.values, (1...50).map { "a->b \($0)" })
    }

    func testOnLineCanBeReassignedMidSession() {
        let input = Channel()
        let first = ReceivedList()
        let second = ReceivedList()
        let link = GameLinkCore(input: input, output: Channel())
        link.onLine = { first.append($0) }

        Protocol.writeLine("one", to: input)
        `await`(first.values.contains("one"))

        link.onLine = { second.append($0) }
        Protocol.writeLine("two", to: input)
        `await`(second.values.contains("two"))

        XCTAssertFalse(first.values.contains("two"))
        XCTAssertEqual(first.values, ["one"])
        XCTAssertEqual(second.values, ["two"])
    }

    func testLinesReceivedBeforeOnLineAttachedAreBuffered() {
        let input = Channel()
        let received = ReceivedList()
        let link = GameLinkCore(input: input, output: Channel())

        Protocol.writeLine("early 1", to: input)
        Thread.sleep(forTimeInterval: 0.05)
        link.onLine = { received.append($0) }

        `await`(received.values == ["early 1"])
        XCTAssertEqual(received.values, ["early 1"])
    }

    func testOnClosedFiresWhenPeerReachesEof() {
        let input = Channel()
        let link = GameLinkCore(input: input, output: Channel())
        link.onLine = { _ in }
        let closed = ClosedFlag()
        link.onClosed = { closed.set(true) }

        input.close()
        `await`(closed.value)
        XCTAssertTrue(closed.value)
    }

    func testCloseIsIdempotent() {
        let input = Channel()
        let closedCount = Counter()
        let link = GameLinkCore(input: input, output: Channel())
        link.onClosed = { closedCount.increment() }
        link.close()
        link.close()
        link.close()
        XCTAssertEqual(closedCount.value, 1)
    }

    func testSendThrowsAfterClose() {
        let link = GameLinkCore(input: Channel(), output: Channel())
        link.close()
        XCTAssertThrowsError(try link.send("hello"))
    }
}

final class InMemoryLinkPairTests: XCTestCase {
    func testPairRoundTripsLines() {
        let (a, b) = InMemoryLinkPair.make()
        let bReceived = ReceivedList()
        b.onLine = { bReceived.append($0) }
        try! a.send("hello over pipe")
        `await`(bReceived.values == ["hello over pipe"])
        XCTAssertEqual(bReceived.values, ["hello over pipe"])
    }
}
