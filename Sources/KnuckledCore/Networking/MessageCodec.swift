import Foundation

public enum MessageCodec {
    public static func encodeState(_ state: GameState) -> String {
        "STATE:" + stateJSON(state)
    }

    public static func stateJSON(_ state: GameState) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try! encoder.encode(state)
        return String(data: data, encoding: .utf8)!
    }

    public static func decodeState(_ line: String) -> GameState? {
        try? decodeStateThrowing(line)
    }

    public static func decodeStateThrowing(_ line: String) throws -> GameState {
        guard line.hasPrefix("STATE:") else {
            throw MessageCodecError.notAStateLine
        }
        let json = String(line.dropFirst("STATE:".count))
        // JSONDecoder requires a Value; `unkeyedContainer` hacks not needed here.
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(GameState.self, from: Data(json.utf8))
        } catch let e as DecodingError {
            throw e
        }
    }

    public enum MessageCodecError: Error { case notAStateLine }
}
