import SwiftUI

struct StreakCard: View {
    let current: Int
    let best: Int
    var sentiment: CardSentiment? = nil

    private var currentColor: Color {
        switch sentiment {
        case .positive: .green
        case .negative: .red
        case nil: .primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconTile(systemName: "flame.fill", tint: .orange)
                Spacer()
            }
            Text("광고 없는 연속 일수")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("현재")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(current)일")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(currentColor)
                    Text(current == 0 ? "오늘 광고를 봤어요" : "광고 없이 연속")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: 12) {
                    Divider().frame(height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("최대")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(best)일")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("역대 최장 기록")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
