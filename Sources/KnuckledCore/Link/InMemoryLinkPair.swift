import Foundation

/// Two in-process GameLinks connected as a loopback pair (like Android's LocalPipe).
public enum InMemoryLinkPair {
    public static func make() -> (GameLink, GameLink) {
        let aToB = Channel()
        let bToA = Channel()
        let a = GameLinkCore(input: bToA, output: aToB)
        let b = GameLinkCore(input: aToB, output: bToA)
        return (a, b)
    }
}
