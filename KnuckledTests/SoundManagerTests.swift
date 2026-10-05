import XCTest
@testable import Knuckled

final class SoundManagerTests: XCTestCase {

    func testFakeRecordsPlaysAndLoops() {
        let sound = FakeSoundManager()
        sound.play(.tap)
        sound.startLoop(.rattle)
        XCTAssertEqual(sound.played, [.tap])
        XCTAssertEqual(sound.looping, .rattle)
        sound.stopLoop()
        XCTAssertNil(sound.looping)
    }

    func testMutedSuppressesEverythingAndKillsLoop() {
        let sound = FakeSoundManager()
        sound.startLoop(.rattle)
        sound.setMuted(true)
        XCTAssertTrue(sound.isMuted)
        XCTAssertNil(sound.looping)
        sound.play(.win)
        sound.startLoop(.land)
        XCTAssertTrue(sound.played.isEmpty)
        XCTAssertNil(sound.looping)
    }

    func testUnmutingResumesPlayback() {
        let sound = FakeSoundManager()
        sound.setMuted(true)
        sound.setMuted(false)
        sound.play(.lose)
        XCTAssertEqual(sound.played, [.lose])
    }
}
