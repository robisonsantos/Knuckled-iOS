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

final class ReceivedList {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

final class ClosedFlag {
    private let lock = NSLock()
    private var flag = false
    func set(_ v: Bool) { lock.lock(); flag = v; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

final class Counter {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// In-memory GameLink recording sent lines; call receive(_:) to simulate the peer.
final class FakeGameLink: GameLink {
    var onLine: ((String) -> Void)?
    var onClosed: (() -> Void)?
    private let lock = NSLock()
    private var _sent: [String] = []
    var sent: [String] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }

    func send(_ line: String) throws {
        lock.lock(); _sent.append(line); lock.unlock()
    }

    func close() {
        onClosed?()
    }

    func receive(_ line: String) {
        onLine?(line)
    }

    var lastState: GameState? {
        lock.lock(); defer { lock.unlock() }
        return _sent.last.flatMap { MessageCodec.decodeState($0) }
    }
}
