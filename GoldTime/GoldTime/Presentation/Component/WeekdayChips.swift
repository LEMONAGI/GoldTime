//
//  WeekdayChips.swift
//  GoldTime
//

import SwiftUI

/// 요일 다중 선택 칩. 요일 라벨은 `Calendar.current.veryShortWeekdaySymbols`(로케일 자동)를 쓰고,
/// 표시 순서는 설정의 주 시작 요일에서 계산한 `orderedIndices`(0=일 … 6=토)를 그대로 따른다.
/// 선택 상태는 `Set<Int>` 바인딩이라 어떤 요일이 골라졌는지 인덱스로 다룬다.
struct WeekdayChips: View {
    /// 표시할 요일 인덱스 순서(0=일 … 6=토). 예: 월 시작이면 [1,2,3,4,5,6,0].
    let orderedIndices: [Int]
    @Binding var selection: Set<Int>

    private var shortSymbols: [String] {
        Calendar.current.veryShortWeekdaySymbols
    }

    private var fullSymbols: [String] {
        Calendar.current.weekdaySymbols
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(orderedIndices, id: \.self) { index in
                chip(for: index)
            }
        }
    }

    @ViewBuilder
    private func chip(for index: Int) -> some View {
        let isSelected = selection.contains(index)
        Button {
            if isSelected {
                selection.remove(index)
            } else {
                selection.insert(index)
            }
        } label: {
            Text(shortSymbols[index])
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .background(isSelected ? Color.accent : Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(fullSymbols[index])
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
