import Foundation

public enum MessageCodec {

    // MARK: Cleanup

    public static func sanitizeName(_ name: String) -> String {
        let control = CharacterSet.controlCharacters
        return name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { char in char.unicodeScalars.allSatisfy { !control.contains($0) } }
    }

    // MARK: Commands

    public static func encodeName(_ name: String) -> String { "NAME:\(sanitizeName(name))" }
    public static func encodeRoll() -> String { "ROLL" }
    public static func encodePlace(_ column: Int) -> String { "PLACE:\(column)" }
    public static func encodeRestart() -> String { "RESTART" }
    public static func encodeState(_ state: GameState) -> String { "STATE:" + stateJSON(state) }

    public static func decodeName(_ line: String) -> String? {
        line.hasPrefix("NAME:") ? String(line.dropFirst("NAME:".count)) : nil
    }

    public static func isRoll(_ line: String) -> Bool { line == "ROLL" }
    public static func isRestart(_ line: String) -> Bool { line == "RESTART" }

    public static func decodePlace(_ line: String) -> Int? {
        guard line.hasPrefix("PLACE:") else { return nil }
        guard let column = Int(line.dropFirst("PLACE:".count)), (0..<3).contains(column) else { return nil }
        return column
    }

    // MARK: State JSON

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
        return try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
    }

    public enum MessageCodecError: Error { case notAStateLine }
}
