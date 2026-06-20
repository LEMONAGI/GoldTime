//
//  SegmentedProgressBar.swift
//  GoldTime
//
//  남은 시간을 숫자가 아니라 고정 칸 수의 블록으로 표현하는 바.
//  이벤트(tick) 1개 = 한 칸으로 매핑해, 한도와 무관하게 항상 한 칸씩 균일하게 줄어든다.
//

import SwiftUI

struct SegmentedProgressBar: View {
    let remaining: Int
    var total: Int = 10
    var tint: Color
    /// VoiceOver로 읽어줄 라벨 (예: "13분 남음"). 비어 있으면 칸 수로 대체.
    var accessibilityText: String = ""

    private var clampedRemaining: Int {
        min(max(remaining, 0), total)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < clampedRemaining ? tint : tint.opacity(0.18))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText.isEmpty ? String(localized: "progress.cellsRemaining \(clampedRemaining)") : accessibilityText)
    }
}
