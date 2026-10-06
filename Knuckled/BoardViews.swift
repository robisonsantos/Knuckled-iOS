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
    /// Top-aligned so a ghost row below one column never shifts its container.
    private var columnsRow: some View {
        HStack(alignment: .top, spacing: 6) {
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
        // Chip outside the outline (Android parity): above the box on our
        // board, below the box (under ghosts) on the peer board.
        return VStack(spacing: 4) {
            if isMine {
                ColumnScoreChip(value: KnucklebonesRules.columnScore(dice))
                    .accessibilityIdentifier("own-chip-\(column)")
                    .accessibilityLabel("own chip \(column)")
            }
            diceBox(cells: cells, placeable: placeable, column: column)
            destroyGhosts(column: column)
            if !isMine {
                ColumnScoreChip(value: KnucklebonesRules.columnScore(dice))
                    .accessibilityIdentifier("peer-chip-\(column)")
                    .accessibilityLabel("peer chip \(column)")
            }
        }
    }

    /// The bordered dice box. Own columns are real Buttons (disabled unless
    /// placeable) so tap state is explicit to VoiceOver and UI tests; peer
    /// columns are never interactive.
    @ViewBuilder
    private func diceBox(cells: [Int?], placeable: Bool, column: Int) -> some View {
        let box = VStack(spacing: 4) {
            ForEach(0..<cells.count, id: \.self) { row in
                DieCell(value: cells[row])
            }
        }
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(placeable ? AppColors.gold : AppColors.glassBorderGold, lineWidth: 1)
        )
        if isMine {
            Button(action: { if placeable { onColumnTap?(column) } }) { box }
                .buttonStyle(.plain)
                .disabled(!placeable)
                .accessibilityIdentifier("own-col-\(column)")
                .accessibilityLabel("own column \(column)")
        } else {
            box
                .accessibilityIdentifier("peer-col-\(column)")
                .accessibilityLabel("peer column \(column)")
        }
    }

    @ViewBuilder
    private func destroyGhosts(column: Int) -> some View {
        DestroyGhosts(ghosts: destroyed.filter { $0.column == column })
    }
}

/// Transient destroy markers: every destroy batch shows a full ~500ms fade
/// (Android parity), even if the previous batch was cancelled mid-fade or the
/// underlying data clears early. Batches render from a local snapshot.
///
/// Driven by onChange(initial:true), NOT .task: this view is usually empty
/// when it first appears, and .task/.onAppear never arm on an empty Group
/// (proven by probe: task never fired, body re-rendered fine). onChange
/// observes values, so it fires reliably here.
struct DestroyGhosts: View {
    let ghosts: [DieRef]
    @State private var showing: [DieRef]?
    @State private var opacity = 0.0
    @State private var generation = 0

    var body: some View {
        Group {
            if let showing {
                HStack(spacing: 4) {
                    ForEach(0..<showing.count, id: \.self) { _ in
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 1, green: 0, blue: 0, opacity: 0.35))
                                .frame(width: 30, height: 30)
                            Text("×").foregroundStyle(.white)
                        }
                    }
                }
                .opacity(opacity)
            }
        }
        .onChange(of: ghosts, initial: true) { _, new in
            guard !new.isEmpty else { return }
            generation += 1
            let myGen = generation
            let batch = new
            showing = batch
            opacity = 1
            // Let the full-opacity frame commit before fading: without this
            // pause the 1→0 sets coalesce and a retriggered batch never
            // visibly appears (proven by ghost-probe screenshots).
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                guard myGen == generation else { return }
                withAnimation(.linear(duration: 0.5)) { opacity = 0 }
                try? await Task.sleep(for: .milliseconds(500))
                guard myGen == generation else { return }
                if showing == batch { showing = nil }
            }
        }
    }
}
