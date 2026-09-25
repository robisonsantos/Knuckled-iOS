import Foundation

/// Blocking byte reader. `readByte()` returns nil at EOF; mirror of `InputStream.read()`.
public protocol ByteSource: AnyObject {
    func readByte() -> Int?
    func close()
}

/// Byte sink; mirror of `OutputStream`.
public protocol ByteSink: AnyObject {
    func write(_ data: Data)
    func close()
}

public enum Protocol {
    public static let maxFrameBytes = 1024

    public static func encode(_ line: String) -> Data {
        var data = Data(line.utf8)
        data.append(0x0A)
        return data
    }

    /// Reads one frame (without the trailing '\n'); nil on EOF or overlong frame.
    public static func readLine(from source: ByteSource) -> String? {
        var buffer = Data()
        while true {
            guard let byte = source.readByte() else { return nil }
            if byte == 0x0A {
                var text = String(data: buffer, encoding: .utf8)
                if let t = text, t.hasSuffix("\r") {
                    text = String(t.dropLast())
                }
                return text
            }
            buffer.append(UInt8(byte))
            if buffer.count > maxFrameBytes { return nil }
        }
    }

    public static func writeLine(_ line: String, to sink: ByteSink) {
        sink.write(encode(line))
    }
}

public enum PinGenerator {
    public static func generate() -> String {
        String(format: "%04d", Int.random(in: 0..<10_000))
    }
}
