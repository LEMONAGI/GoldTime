//
//  SectionHeader.swift
//  GoldTime
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    let systemName: String?

    init(title: String, systemName: String? = nil) {
        self.title = title
        self.systemName = systemName
    }

    var body: some View {
        HStack(spacing: 8) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.accent)
            }
            Text(title)
                .font(.headline)
        }
    }
}
