import XCTest
@testable import Knuckled

final class DiceOrientationTests: XCTestCase {

    func testFaceTableMatchesAndroid() {
        XCTAssertEqual(DiceOrientation.eulerForFace(1), SIMD3(-90, 0, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(2), SIMD3(0, 0, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(3), SIMD3(0, -90, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(4), SIMD3(0, 90, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(5), SIMD3(0, 180, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(6), SIMD3(90, 0, 0))
    }

    func testUnknownFaceFallsBackToIdentity() {
        XCTAssertEqual(DiceOrientation.eulerForFace(0), SIMD3(0, 0, 0))
        XCTAssertEqual(DiceOrientation.eulerForFace(7), SIMD3(0, 0, 0))
    }

    func testProceduralFaceMapSumsToSeven() {
        // Opposite faces sum to 7 (standard die): materials [+x,-x,+y,-y,+z,-z].
        let faces = DiceOrientation.proceduralFaces
        XCTAssertEqual(faces, [3, 4, 6, 1, 2, 5])
        XCTAssertEqual(faces[0] + faces[1], 7)
        XCTAssertEqual(faces[2] + faces[3], 7)
        XCTAssertEqual(faces[4] + faces[5], 7)
        XCTAssertEqual(faces[4], 2) // identity (+z toward camera) shows 2, per the table
    }
}
