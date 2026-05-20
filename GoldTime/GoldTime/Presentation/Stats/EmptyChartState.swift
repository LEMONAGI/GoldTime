//
//  EmptyChartState.swift
//  GoldTime
//

import SwiftUI

struct EmptyChartState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accent)
            Text("추가 사용 기록이 생기면 여기에 쌓입니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
