import Foundation

/// The seam the whole game talks over: a full-duplex line channel.
/// `send` throws after close; `onClosed` fires at most once.
/// Callers MUST call `close()` when done: the reader thread retains the link
/// until the input is closed, so a never-closed link parks a thread for the
/// process lifetime.
public protocol GameLink: AnyObject {
    var onLine: ((String) -> Void)? { get set }
    var onClosed: (() -> Void)? { get set }
    func send(_ line: String) throws
    func close()
}

public enum GameLinkError: Error {
    case closed
}
