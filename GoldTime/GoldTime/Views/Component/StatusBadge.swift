import SwiftUI

struct StatusBadge: View {
    let title: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct GroupStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .lineLimit(1)
    }
}
