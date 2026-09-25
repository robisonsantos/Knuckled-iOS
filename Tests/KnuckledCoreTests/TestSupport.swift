import Foundation
import XCTest
@testable import KnuckledCore

/// Waits (up to timeoutMs) until condition() is true, then XCTFails on timeout.
func await(timeoutMs: Int = 2000, _ condition: @autoclosure () -> Bool,
           file: StaticString = #filePath, line: UInt = #line) {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
    while !condition() {
        if Date() > deadline {
            XCTFail("Timed out waiting for condition", file: file, line: line)
            return
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
}
