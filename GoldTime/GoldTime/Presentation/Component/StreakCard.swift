import SwiftUI

struct StreakCard: View {
    let current: Int
    let best: Int
    var sentiment: CardSentiment? = nil

    private var currentColor: Color {
        switch sentiment {
        case .positive: .green
        case .negative: .red
        case .neutral: .orange
        case nil: .primary
        }
    }

    private var bestColor: Color {
        current > 0 && current >= best ? .green : .primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconTile(systemName: "flame.fill", tint: .orange)
                Spacer()
            }
            Text("stats.streak.title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("stats.streak.current")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("common.days \(current)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(currentColor)
                    Text(current == 0 ? "stats.streak.watchedToday" : "stats.streak.adFree")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: 12) {
                    Divider().frame(height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("stats.streak.best")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("common.days \(best)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(bestColor)
                        Text("stats.streak.record")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
