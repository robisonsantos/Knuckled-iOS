import Foundation

public enum PlayerId: String, Codable, CaseIterable, Sendable { case HOST, CLIENT }
public enum Status: String, Codable, CaseIterable, Sendable { case IN_PROGRESS, FINISHED, DRAW }
public enum Phase: String, Codable, CaseIterable, Sendable { case IDLE, ROLLING, AWAITING_PLACEMENT }

/// A single column of a board: each die is its face value 1...6, bottom-most die first.
public typealias Column = [Int]

/// A 3x3 board: three columns, each holding up to KnucklebonesRules.columnSize dice.
public typealias Grid = [Column]

/// Captures every key present in the JSON object, including unknown ones.
/// (A container keyed by a String `CodingKeys` enum silently drops unknown
/// keys from `allKeys`, so strict rejection must go through this type.)
private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A die destroyed by an opponent's placement, so the UI can animate it.
public struct DieRef: Codable, Equatable, Sendable {
    public var player: PlayerId
    public var column: Int
    public var value: Int

    public init(player: PlayerId, column: Int, value: Int) {
        self.player = player
        self.column = column
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case player, column, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try Self.rejectUnknownKeys(decoder: decoder)
        player = try c.decode(PlayerId.self, forKey: .player)
        column = try c.decode(Int.self, forKey: .column)
        value = try c.decode(Int.self, forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(player, forKey: .player)
        try c.encode(column, forKey: .column)
        try c.encode(value, forKey: .value)
    }

    private static func rejectUnknownKeys(decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        if let unknown = raw.allKeys.map(\.stringValue).first(where: { !known.contains($0) }) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown key '\(unknown)'"))
        }
    }
}

public struct GameState: Codable, Equatable, Sendable {
    public var hostName: String
    public var clientName: String
    public var status: Status
    public var currentTurn: PlayerId
    public var phase: Phase
    public var grid: [PlayerId: Grid]
    public var winner: PlayerId?
    public var lastRoll: Int?
    public var destroyed: [DieRef]

    public init(hostName: String,
                clientName: String,
                status: Status,
                currentTurn: PlayerId,
                phase: Phase,
                grid: [PlayerId: Grid],
                winner: PlayerId? = nil,
                lastRoll: Int? = nil,
                destroyed: [DieRef] = []) {
        self.hostName = hostName
        self.clientName = clientName
        self.status = status
        self.currentTurn = currentTurn
        self.phase = phase
        self.grid = grid
        self.winner = winner
        self.lastRoll = lastRoll
        self.destroyed = destroyed
    }

    public func playerName(_ player: PlayerId) -> String {
        player == .HOST ? hostName : clientName
    }

    public func opponentOf(_ player: PlayerId) -> PlayerId {
        player == .HOST ? .CLIENT : .HOST
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case hostName, clientName, status, currentTurn, phase, grid, winner, lastRoll, destroyed
    }

    private static func rejectUnknownKeys(decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        if let unknown = raw.allKeys.map(\.stringValue).first(where: { !known.contains($0) }) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown key '\(unknown)'"))
        }
    }

    public init(from decoder: Decoder) throws {
        try Self.rejectUnknownKeys(decoder: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hostName = try c.decode(String.self, forKey: .hostName)
        clientName = try c.decode(String.self, forKey: .clientName)
        status = try c.decode(Status.self, forKey: .status)
        currentTurn = try c.decode(PlayerId.self, forKey: .currentTurn)
        phase = try c.decode(Phase.self, forKey: .phase)
        // Swift's JSONDecoder encodes [PlayerId: Grid] as an array, not an object,
        // so bridge via [String: Grid] to match the Android wire schema
        // {"HOST": [...], "CLIENT": [...]}.
        let stringGrid = try c.decode([String: Grid].self, forKey: .grid)
        var mappedGrid: [PlayerId: Grid] = [:]
        for (key, value) in stringGrid {
            guard let player = PlayerId(rawValue: key) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown grid key '\(key)'"))
            }
            mappedGrid[player] = value
        }
        grid = mappedGrid
        winner = try c.decodeIfPresent(PlayerId.self, forKey: .winner)
        lastRoll = try c.decodeIfPresent(Int.self, forKey: .lastRoll)
        destroyed = try c.decodeIfPresent([DieRef].self, forKey: .destroyed) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        // Same field order and explicit-null behaviour as kotlinx.serialization
        // with encodeDefaults=true (empty defaults and nulls are emitted).
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hostName, forKey: .hostName)
        try c.encode(clientName, forKey: .clientName)
        try c.encode(status, forKey: .status)
        try c.encode(currentTurn, forKey: .currentTurn)
        try c.encode(phase, forKey: .phase)
        // Bridge via [String: Grid] so the wire form is a JSON object keyed by
        // "HOST"/"CLIENT" (see decoding note above).
        let stringGrid = Dictionary(uniqueKeysWithValues: grid.map { ($0.key.rawValue, $0.value) })
        try c.encode(stringGrid, forKey: .grid)
        if let winner { try c.encode(winner, forKey: .winner) } else { try c.encodeNil(forKey: .winner) }
        if let lastRoll { try c.encode(lastRoll, forKey: .lastRoll) } else { try c.encodeNil(forKey: .lastRoll) }
        try c.encode(destroyed, forKey: .destroyed)
    }
}
