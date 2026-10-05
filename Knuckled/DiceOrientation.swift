import Foundation
import simd

/// Rolled value → XYZ Euler degrees putting that face on +Z.
/// Android parity: `DiceCube.getRotationForFace` verbatim.
enum DiceOrientation {
    static func eulerForFace(_ value: Int) -> SIMD3<Double> {
        switch value {
        case 1: return SIMD3(-90, 0, 0)
        case 3: return SIMD3(0, -90, 0)
        case 4: return SIMD3(0, 90, 0)
        case 5: return SIMD3(0, 180, 0)
        case 6: return SIMD3(90, 0, 0)
        default: return SIMD3(0, 0, 0) // 2 and unknown
        }
    }

    /// Procedural fallback face order for SCNBox materials [+x,-x,+y,-y,+z,-z].
    /// Chosen so the Euler table above holds: identity shows +z = 2, and every
    /// mapped rotation lands its value on +z (opposites sum to 7).
    static let proceduralFaces = [3, 4, 6, 1, 2, 5]
}
