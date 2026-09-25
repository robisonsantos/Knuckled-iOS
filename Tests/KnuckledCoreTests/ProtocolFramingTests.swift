import XCTest
@testable import KnuckledCore

final class ProtocolFramingTests: XCTestCase {

    func testEncodeAppendsNewlineInUtf8() {
        XCTAssertEqual(Protocol.encode("hi"), Data("hi\n".utf8))
    }

    func testEncodeHandlesUnicode() {
        XCTAssertEqual(Protocol.encode("héllo 世界"), Data("héllo 世界\n".utf8))
    }

    func testReadLineReadsUtf8Lines() {
        let ch = Channel()
        ch.write(Data("one\ntwo\n".utf8))
        ch.close()
        XCTAssertEqual(Protocol.readLine(from: ch), "one")
        XCTAssertEqual(Protocol.readLine(from: ch), "two")
        XCTAssertNil(Protocol.readLine(from: ch))
    }

    func testReadLineReturnsNilOnEof() {
        let ch = Channel()
        ch.close()
        XCTAssertNil(Protocol.readLine(from: ch))
    }

    func testReadLineStripsTrailingCarriageReturn() {
        let ch = Channel()
        ch.write(Data("one\r\n".utf8))
        ch.close()
        XCTAssertEqual(Protocol.readLine(from: ch), "one")
    }

    func testWriteLineRoundTripsThroughChannel() {
        let ch = Channel()
        Protocol.writeLine("hello", to: ch)
        ch.close()
        XCTAssertEqual(Protocol.readLine(from: ch), "hello")
    }

    func testReadLineRejectsOverlongFrameWithoutThrowing() {
        let ch = Channel()
        ch.write(Data(String(repeating: "x", count: Protocol.maxFrameBytes + 1).utf8))
        ch.write(Data("\n".utf8))
        ch.close()
        XCTAssertNil(Protocol.readLine(from: ch))
    }
}
