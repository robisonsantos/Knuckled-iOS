import Foundation

/// Thread-safe in-memory byte pipe for one direction. Both a ByteSource
/// (reader side blocks until data or EOF) and a ByteSink (writer side).
public final class Channel: ByteSource, ByteSink {
    private var buffer = Data()
    private var isClosed = false
    private let cond = NSCondition()

    public init() {}

    public func write(_ data: Data) {
        cond.lock()
        if !isClosed { buffer.append(data) }
        cond.signal()
        cond.unlock()
    }

    public func readByte() -> Int? {
        cond.lock()
        defer { cond.unlock() }
        while buffer.isEmpty && !isClosed {
            cond.wait()
        }
        if buffer.isEmpty { return nil }
        return Int(buffer.removeFirst())
    }

    public func close() {
        cond.lock()
        isClosed = true
        cond.broadcast()
        cond.unlock()
    }
}
