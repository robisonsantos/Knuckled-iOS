import XCTest
@testable import KnuckledCore

final class HandshakeTests: XCTestCase {

    private final class ResultBox {
        private let lock = NSLock()
        private var val: Bool?
        func set(_ v: Bool) { lock.lock(); val = v; lock.unlock() }
        var value: Bool? { lock.lock(); defer { lock.unlock() }; return val }
    }

    func testCorrectPinSucceedsOnBothEnds() {
        let hostToClient = Channel()
        let clientToHost = Channel()
        let pin = "4321"
        let hostResult = ResultBox()
        let clientResult = ResultBox()

        DispatchQueue.global().async {
            hostResult.set(Handshake.accept(source: clientToHost, sink: hostToClient, expectedPin: pin))
        }
        DispatchQueue.global().async {
            clientResult.set(Handshake.initiate(source: hostToClient, sink: clientToHost, pin: pin))
        }
        `await`(hostResult.value != nil && clientResult.value != nil)
        XCTAssertEqual(hostResult.value, true)
        XCTAssertEqual(clientResult.value, true)
    }

    func testWrongPinFailsOnBothEnds() {
        let hostToClient = Channel()
        let clientToHost = Channel()
        let hostResult = ResultBox()
        let clientResult = ResultBox()

        DispatchQueue.global().async {
            hostResult.set(Handshake.accept(source: clientToHost, sink: hostToClient, expectedPin: "4321"))
        }
        DispatchQueue.global().async {
            clientResult.set(Handshake.initiate(source: hostToClient, sink: clientToHost, pin: "0000"))
        }
        `await`(hostResult.value != nil && clientResult.value != nil)
        XCTAssertEqual(hostResult.value, false)
        XCTAssertEqual(clientResult.value, false)
    }

    func testAcceptReturnsFalseWhenPeerIsEof() {
        let empty = Channel()
        empty.close()
        XCTAssertFalse(Handshake.accept(source: empty, sink: Channel(), expectedPin: "1234"))
    }

    func testInitiateReturnsFalseWhenPeerSendsNoReply() {
        let noReply = Channel()
        noReply.close()
        XCTAssertFalse(Handshake.initiate(source: noReply, sink: Channel(), pin: "1234"))
    }

    func testInitiateReturnsFalseWhenPeerSendsInvalid() {
        let ch = Channel()
        ch.write(Data("INVALID\n".utf8))
        ch.close()
        XCTAssertFalse(Handshake.initiate(source: ch, sink: Channel(), pin: "1234"))
    }
}
