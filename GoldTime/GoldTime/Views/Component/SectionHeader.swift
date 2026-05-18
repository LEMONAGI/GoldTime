//
//  SectionHeader.swift
//  GoldTime
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    let systemName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accent)
            Text(title)
                .font(.headline)
        }
    }
}
