//
//  BillPill.swift
//  GoldTime
//

import SwiftUI

struct BillPill: View {
    let title: String
    let value: String
    var accentValue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(accentValue ? Color.accent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
