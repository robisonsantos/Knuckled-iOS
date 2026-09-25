import Foundation

/// CPU playing the client side: sends NAME, rolls on its turn, places via CpuPlayer.
public func runCpuClient(
    _ link: GameLink,
    preRollDelayMs: Double = CpuPacing.preRollSeconds,
    thinkDelay: @escaping () -> Double = CpuPacing.naturalThink,
    choose: @escaping (GameState) -> Int = { CpuPlayer.chooseColumn($0) }
) {
    link.onLine = { [weak link] line in
        guard let link else { return }
        guard let state = MessageCodec.decodeState(line) else { return }
        if KnucklebonesRules.canRoll(state, .CLIENT) {
            delayed(preRollDelayMs) { try? link.send(MessageCodec.encodeRoll()) }
        }
        if state.phase == .AWAITING_PLACEMENT && state.currentTurn == .CLIENT {
            let column = choose(state)
            delayed(thinkDelay()) { try? link.send(MessageCodec.encodePlace(column)) }
        }
    }
    try? link.send(MessageCodec.encodeName(CpuPlayer.name))
}
