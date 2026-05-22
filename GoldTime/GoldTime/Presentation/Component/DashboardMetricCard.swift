import SwiftUI

struct DashboardMetricCard: View {
    let title: String
    let value: String
    let caption: String
    let systemName: String
    let tint: Color
    var trend: TrendDirection? = nil

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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let trend, trend != .flat {
                        Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                            .font(.title3.weight(.bold))
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
