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

/// GameLink whose send(_:) hands lines to the host and whose onLine can be driven externally.
final class ProxyLink: GameLink {
    var onLine: ((String) -> Void)?
    var onClosed: (() -> Void)?
    private let receiveToHost: (String) -> Void
    private let onClose: (() -> Void)

    init(receiveToHost: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.receiveToHost = receiveToHost
        self.onClose = onClose
    }

    func send(_ line: String) throws { receiveToHost(line) }
    func close() { onClose() }
}
