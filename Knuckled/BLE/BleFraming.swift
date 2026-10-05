import Foundation

/// GATT sender chunking (spec framing section): each \n-terminated UTF-8
/// line splits into consecutive chunks of at most (MTU − 3) bytes, 20-byte
/// fallback when the MTU is unknown. No length prefix. The receiver side is
/// `Protocol.readLine` inside `GameLinkCore` (byte-wise split on \n,
/// \r-strip, 1024 cap, overlong fatal) — shared with every transport.
enum BleFraming {
    static func chunkSize(mtu: Int?) -> Int {
        max((mtu ?? 23) - 3, 1)
    }

    static func chunkData(_ data: Data, mtu: Int?) -> [Data] {
        let size = chunkSize(mtu: mtu)
        var out: [Data] = []
        var i = data.startIndex
        while i < data.endIndex {
            let j = data.index(i, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            out.append(data[i..<j])
            i = j
        }
        return out
    }

    static func chunk(line: String, mtu: Int?) -> [Data] {
        var bytes = Data(line.utf8)
        bytes.append(0x0A)
        return chunkData(bytes, mtu: mtu)
    }
}
