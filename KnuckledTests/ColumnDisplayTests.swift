import XCTest
@testable import Knuckled

final class ColumnDisplayTests: XCTestCase {
    func testOwnColumnPadsBelow() {
        XCTAssertEqual(ownColumnTopToBottom([4, 1, 4]), [4, 1, 4])
        XCTAssertEqual(ownColumnTopToBottom([4]), [4, nil, nil])
        XCTAssertEqual(ownColumnTopToBottom([]), [nil, nil, nil])
    }

    func testPeerColumnPadsAbove() {
        XCTAssertEqual(peerColumnTopToBottom([3, 3]), [nil, 3, 3])
        XCTAssertEqual(peerColumnTopToBottom([]), [nil, nil, nil])
        XCTAssertEqual(peerColumnTopToBottom([2, 3]), [nil, 3, 2])
    }
}
