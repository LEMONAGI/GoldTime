import SwiftUI

enum CardSentiment {
    case positive, negative
}

struct DashboardMetricCard: View {
    let title: String
    let value: String
    let caption: String
    let systemName: String
    let tint: Color
    var trend: TrendDirection? = nil
    var sentiment: CardSentiment? = nil

    private var valueColor: Color {
        switch sentiment {
        case .positive: .green
        case .negative: .red
        case nil: .primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconTile(systemName: systemName, tint: tint)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let trend, trend != .flat {
                        Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                            .font(.body.weight(.bold))
                            .foregroundStyle(trend == .up ? Color.red : Color.green)
                    }
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
