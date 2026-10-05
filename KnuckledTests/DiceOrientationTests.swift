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
        // Opposite faces sum to 7 (standard die): SCNBox materials are
        // [front, right, back, left, top, bottom] = [+z,+x,-z,-x,+y,-y].
        let faces = DiceOrientation.proceduralFaces
        XCTAssertEqual(faces, [2, 3, 5, 4, 6, 1])
        XCTAssertEqual(faces[0] + faces[2], 7) // front + back
        XCTAssertEqual(faces[1] + faces[3], 7) // right + left
        XCTAssertEqual(faces[4] + faces[5], 7) // top + bottom
        XCTAssertEqual(faces[0], 2) // identity (front +z toward camera) shows 2
    }
}
