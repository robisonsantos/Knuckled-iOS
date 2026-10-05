import XCTest
@testable import Knuckled
@testable import KnuckledCore
import CoreBluetooth

final class BlePipeTests: XCTestCase {

    func testWriteChunksByMtuAndRoundTripsThroughFeed() {
        let pipe = BlePipe()
        pipe.mtu = 23
        var sent: [Data] = []
        pipe.onWrite = { data, _ in sent.append(data) }
        pipe.write(Data("ROLL\n".utf8))
        XCTAssertEqual(sent, [Data("ROLL\n".utf8)])
        for chunk in sent { pipe.feed(chunk) }
        XCTAssertEqual(Protocol.readLine(from: pipe), "ROLL")
    }

    func testLongWriteSplitsToMtuChunks() {
        let pipe = BlePipe()
        pipe.mtu = 23
        var sent: [Data] = []
        pipe.onWrite = { data, _ in sent.append(data) }
        let line = Data(String(repeating: "x", count: 50).utf8)
        pipe.write(line)
        XCTAssertEqual(sent.count, 3)
        XCTAssertTrue(sent.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(sent.reduce(Data(), +), line)
    }

    func testWriteModePassedThrough() {
        let pipe = BlePipe()
        var modes: [CBCharacteristicWriteType] = []
        pipe.onWrite = { _, mode in modes.append(mode) }
        pipe.writeMode = .withResponse
        pipe.write(Data("PIN:1\n".utf8))
        XCTAssertEqual(modes, [.withResponse])
    }

    func testCloseUnblocksReaderAndDropsWrites() {
        let pipe = BlePipe()
        var writes = 0
        pipe.onWrite = { _, _ in writes += 1 }
        pipe.close()
        pipe.write(Data("x\n".utf8))
        XCTAssertEqual(writes, 0)
        XCTAssertNil(pipe.readByte())
        pipe.close() // idempotent, no crash
    }

    func testOverlongFrameIsFatalLikeProtocol() {
        let pipe = BlePipe()
        pipe.feed(Data(repeating: UInt8(ascii: "x"), count: 1025))
        pipe.feed(Data("\n".utf8))
        XCTAssertNil(Protocol.readLine(from: pipe))
    }
}
