import Foundation

/// Concrete GameLink over a blocking ByteSource/ByteSink using Protocol framing.
/// A reader thread continuously reads framed lines and dispatches to onLine;
/// on EOF it fires onClosed and closes the link. Lines received before onLine
/// is attached are buffered so no line is dropped (register-after-start).
public final class GameLinkCore: GameLink {
    public var onLine: ((String) -> Void)? {
        didSet {
            lock.lock()
            onLineAttached = true
            let toDeliver = pending
            pending = []
            lock.unlock()
            toDeliver.forEach { onLine?($0) }
        }
    }

    public var onClosed: (() -> Void)?

    private let input: ByteSource
    private let output: ByteSink
    private let lock = NSLock()
    private var pending: [String] = []
    private var onLineAttached = false
    private var running = true
    private var closed = false

    public init(input: ByteSource, output: ByteSink) {
        self.input = input
        self.output = output
        startReading()
    }

    public func send(_ line: String) throws {
        lock.lock()
        if closed {
            lock.unlock()
            throw GameLinkError.closed
        }
        lock.unlock()
        Protocol.writeLine(line, to: output)
    }

    public func close() {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        lock.unlock()
        onClosed?()
        running = false
        input.close()
        output.close()
    }

    private func startReading() {
        Thread.detachNewThread { [weak self] in
            guard let self else { return }
            while self.running {
                guard let line = Protocol.readLine(from: self.input) else { break }
                self.dispatch(line)
            }
            self.close()
        }
    }

    private func dispatch(_ line: String) {
        let handler: ((String) -> Void)?
        lock.lock()
        if onLineAttached, let h = onLine {
            handler = h
        } else {
            pending.append(line)
            handler = nil
        }
        lock.unlock()
        handler?(line)
    }
}
