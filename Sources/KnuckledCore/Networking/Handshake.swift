import Foundation

public enum Handshake {
    public static let pinPrefix = "PIN:"
    public static let ok = "OK"
    public static let invalid = "INVALID"

    /// Host side: expect a PIN line, verify against expectedPin, reply OK/INVALID.
    public static func accept(source: ByteSource, sink: ByteSink, expectedPin: String) -> Bool {
        guard let line = Protocol.readLine(from: source) else { return false }
        let matches = line.hasPrefix(pinPrefix) && String(line.dropFirst(pinPrefix.count)) == expectedPin
        Protocol.writeLine(matches ? ok : invalid, to: sink)
        return matches
    }

    /// Client side: send pin, wait for OK/INVALID.
    public static func initiate(source: ByteSource, sink: ByteSink, pin: String) -> Bool {
        Protocol.writeLine("\(pinPrefix)\(pin)", to: sink)
        return Protocol.readLine(from: source) == ok
    }
}
