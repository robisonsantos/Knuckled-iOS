import XCTest
@testable import KnuckledCore

final class PinGeneratorTests: XCTestCase {

    func testGeneratesFourDigitPinsAcrossRange() {
        for _ in 0..<1000 {
            let pin = PinGenerator.generate()
            XCTAssertTrue(pin.count == 4 && pin.allSatisfy(\.isNumber), "pin should be 4 digits, was '\(pin)'")
            let value = Int(pin)!
            XCTAssertTrue((0...9999).contains(value), "pin out of numeric range, was '\(pin)'")
        }
    }
}
