import Foundation
import CoreBluetooth
import KnuckledCore

/// Blocking duplex byte pipe over CoreBluetooth callbacks. Inbound chunks
/// (central writes / notify updates) arrive via `feed` on any thread;
/// outbound lines chunk by MTU through `onWrite`. `GameLinkCore` owns
/// framing (`Protocol.readLine`, 1024 cap) and close semantics on top.
final class BlePipe: ByteSource, ByteSink {
    var mtu: Int?
    var writeMode: CBCharacteristicWriteType = .withoutResponse
    var onWrite: ((Data, CBCharacteristicWriteType) -> Void)?
    var onClose: (() -> Void)?

    private var inbound = Data()
    private var closed = false
    private let cond = NSCondition()

    func feed(_ chunk: Data) {
        cond.lock()
        if !closed { inbound.append(chunk) }
        cond.signal()
        cond.unlock()
    }

    // MARK: ByteSource

    func readByte() -> Int? {
        cond.lock()
        defer { cond.unlock() }
        while inbound.isEmpty && !closed {
            cond.wait()
        }
        if inbound.isEmpty { return nil }
        return Int(inbound.removeFirst())
    }

    // MARK: ByteSink

    func write(_ data: Data) {
        let chunks = BleFraming.chunkData(data, mtu: mtu)
        let handler = onWrite
        let isClosed: Bool = {
            cond.lock()
            defer { cond.unlock() }
            return closed
        }()
        guard !isClosed else { return }
        for chunk in chunks { handler?(chunk, writeMode) }
    }

    func close() {
        cond.lock()
        let first = !closed
        closed = true
        cond.broadcast()
        cond.unlock()
        if first { onClose?() }
    }
}
