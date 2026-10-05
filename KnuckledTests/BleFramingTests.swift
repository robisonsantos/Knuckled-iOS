import XCTest
@testable import Knuckled
import CoreBluetooth

final class BleFramingTests: XCTestCase {

    func testFrozenUUIDs() {
        XCTAssertEqual(BleUUIDs.service, CBUUID(string: "8B6B4A85-57B3-4BE8-ACDE-BE209FBAAE7A"))
        XCTAssertEqual(BleUUIDs.write, CBUUID(string: "AAF90241-0F50-42CF-ADFC-2BAADE92ACD1"))
        XCTAssertEqual(BleUUIDs.notify, CBUUID(string: "3FE6B62B-8DF0-4B4D-BB7E-8048B74461AA"))
        XCTAssertEqual(BleUUIDs.localName, "Knuckled")
    }

    func testChunkSizeDefaults() {
        XCTAssertEqual(BleFraming.chunkSize(mtu: nil), 20)
        XCTAssertEqual(BleFraming.chunkSize(mtu: 23), 20)
        XCTAssertEqual(BleFraming.chunkSize(mtu: 185), 182)
        XCTAssertEqual(BleFraming.chunkSize(mtu: 3), 1)
    }

    func testShortLineIsOneChunk() {
        let chunks = BleFraming.chunk(line: "ROLL", mtu: nil)
        XCTAssertEqual(chunks, [Data("ROLL\n".utf8)])
    }

    func testLongLineSplitsAndRejoinsByteExact() {
        let line = "STATE:" + String(repeating: "héllo 世界", count: 40)
        let chunks = BleFraming.chunk(line: line, mtu: nil)
        XCTAssertTrue(chunks.count > 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(chunks.reduce(Data(), +), Data((line + "\n").utf8))
    }

    func testMultiByteCharacterSurvivesChunkBoundary() {
        // "é" is 2 bytes in UTF-8; 20-byte chunks will split mid-character.
        let line = String(repeating: "é", count: 30)
        let chunks = BleFraming.chunk(line: line, mtu: nil)
        XCTAssertEqual(chunks.reduce(Data(), +), Data((line + "\n").utf8))
    }

    func testChunkDataSplitsRawBytes() {
        let data = Data((0..<55).map { UInt8($0) })
        let chunks = BleFraming.chunkData(data, mtu: 23)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, 20)
        XCTAssertEqual(chunks[2].count, 15)
        XCTAssertEqual(chunks.reduce(Data(), +), data)
    }
}
