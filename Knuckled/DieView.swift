import SwiftUI

/// Temporary 2D pip die (120pt). The SceneKit 3D die replaces this in the parity plan.
/// Same contract: fixed size, tap only when enabled && !rolling, spinning cue while rolling.
struct DieView: View {
    let value: Int?
    let rolling: Bool
    let enabled: Bool
    let onTap: () -> Void

    private static func pips(for value: Int) -> Set<Int> {
        switch value {
        case 1: return [5]
        case 2: return [1, 9]
        case 3: return [1, 5, 9]
        case 4: return [1, 3, 7, 9]
        case 5: return [1, 3, 5, 7, 9]
        case 6: return [1, 3, 4, 6, 7, 9]
        default: return []
        }
    }

    var body: some View {
        Button(action: {
            if enabled && !rolling { onTap() }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(AppColors.dieIvoryLight)
                    .frame(width: 120, height: 120)
                GeometryReader { geo in
                    let cell = min(geo.size.width, geo.size.height) / 3
                    ForEach(1...9, id: \.self) { pos in
                        if Self.pips(for: value ?? 0).contains(pos) {
                            Circle()
                                .fill(AppColors.pipBrown)
                                .frame(width: cell * 0.52, height: cell * 0.52)
                                .position(
                                    x: cell * (CGFloat((pos - 1) % 3) + 0.5),
                                    y: cell * (CGFloat((pos - 1) / 3) + 0.5)
                                )
                        }
                    }
                }
                .frame(width: 120, height: 120)
            }
            .rotationEffect(.degrees(rolling ? 360 : 0))
            .animation(rolling ? .linear(duration: 1.0) : .default, value: rolling)
            .opacity(value == nil && !rolling ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(!(enabled && !rolling))
        .accessibilityIdentifier("dice")
        .accessibilityLabel(rolling ? "Dice rolling" : value.map { "Dice showing \($0)" } ?? "Dice tap to roll")
    }
}
