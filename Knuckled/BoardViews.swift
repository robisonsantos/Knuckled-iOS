import SwiftUI
import KnuckledCore

/// Own board: oldest die nearest the middle (top). Returns exactly 3 rows, top-anchored.
func ownColumnTopToBottom(_ dice: [Int]) -> [Int?] {
    dice.map { Optional($0) } + Array(repeating: nil, count: max(0, 3 - dice.count))
}

/// Peer board: oldest die nearest the middle (bottom). Returns exactly 3 rows, bottom-anchored.
func peerColumnTopToBottom(_ dice: [Int]) -> [Int?] {
    Array(repeating: nil, count: max(0, 3 - dice.count)) + dice.reversed().map { Optional($0) }
}

struct DieCell: View {
    let value: Int?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(value == nil ? Color(red: 1, green: 1, blue: 1, opacity: 0.25) : AppColors.glassWhite)
                .frame(width: 52, height: 52)
            if let value {
                Text("\(value)")
                    .font(.title3.bold())
                    .foregroundStyle(AppColors.ivory)
            }
        }
        .padding(3)
    }
}

struct ColumnScoreChip: View {
    let value: Int
    var body: some View {
        Text("\(value)")
            .font(.caption2)
            .foregroundStyle(AppColors.gold)
            .frame(width: 44, height: 18)
            .background(AppColors.glassWhite)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct GameBoard: View {
    let isMine: Bool
    let name: String
    let grid: KnuckledCore.Grid
    let destroyed: [DieRef]
    let active: Bool
    let canPlace: Bool
    let onColumnTap: ((Int) -> Void)?

    private func columnPlaceable(_ column: Int) -> Bool {
        guard column < grid.count else { return false }
        return onColumnTap != nil && active && canPlace && grid[column].count < 3
    }

    var body: some View {
        VStack(spacing: 6) {
            if isMine {
                columnsRow
                header
            } else {
                header
                columnsRow
            }
        }
    }

    /// The three columns side by side (Android: Row + SpaceEvenly).
    private var columnsRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { column in
                columnView(column)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(name)
                .font(.headline)
                .foregroundStyle(AppColors.gold)
            Spacer()
            Text("\(KnucklebonesRules.totalScore(grid))")
                .font(.title2.bold())
                .foregroundStyle(AppColors.ivory)
                .accessibilityIdentifier(isMine ? "score-mine" : "score-peer")
        }
    }

    private func columnView(_ column: Int) -> some View {
        let dice = column < grid.count ? grid[column] : []
        let cells = isMine ? ownColumnTopToBottom(dice) : peerColumnTopToBottom(dice)
        let placeable = columnPlaceable(column)
        return VStack(spacing: 4) {
            VStack(spacing: 4) {
                if isMine { ColumnScoreChip(value: KnucklebonesRules.columnScore(dice)) }
                ForEach(0..<cells.count, id: \.self) { row in
                    DieCell(value: cells[row])
                }
                if !isMine { ColumnScoreChip(value: KnucklebonesRules.columnScore(dice)) }
            }
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(placeable ? AppColors.gold : AppColors.glassBorderGold, lineWidth: 1)
            )
            .accessibilityIdentifier("\(isMine ? "own" : "peer")-col-\(column)")
            .accessibilityLabel("\(isMine ? "own" : "peer") column \(column)")
            .onTapGesture {
                if placeable { onColumnTap?(column) }
            }
            destroyGhosts(column: column)
        }
    }

    @ViewBuilder
    private func destroyGhosts(column: Int) -> some View {
        let ghosts = destroyed.filter { $0.column == column }
        if !ghosts.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<ghosts.count, id: \.self) { _ in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 1, green: 0, blue: 0, opacity: 0.35))
                            .frame(width: 30, height: 30)
                        Text("×").foregroundStyle(.white)
                    }
                }
            }
            .transition(.opacity)
        }
    }
}
