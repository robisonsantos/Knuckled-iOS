import Foundation

/// The seam the whole game talks over: a full-duplex line channel.
/// `send` throws after close; `onClosed` fires at most once.
public protocol GameLink: AnyObject {
    var onLine: ((String) -> Void)? { get set }
    var onClosed: (() -> Void)? { get set }
    func send(_ line: String) throws
    func close()
}

public enum GameLinkError: Error {
    case closed
}
