//
//  CountUpDurationText.swift
//  GoldTime
//
//  시간 청구액(초과 사용 시간)을 표시하는 텍스트. 값이 늘어나면 숫자가 쫘라락 카운트업된다.
//

import SwiftUI

/// `billTotalText`와 동일한 포맷(`0분` / `+N분`)으로 표시하되, 값이 증가하면 카운트업 애니메이션을 준다.
/// - 콜드 진입 시에는 애니메이션 없이 현재 값으로 시작한다.
/// - 1초 주기 갱신으로 상위 뷰가 재생성돼도 `@State`는 뷰 identity로 유지되어, 값이 실제로 바뀔 때만 애니메이션한다.
struct CountUpDurationText: View {
    let seconds: Int

    @State private var displayed: Double = 0

    var body: some View {
        AnimatableDurationText(value: displayed)
            .onAppear { displayed = Double(seconds) }
            .onChange(of: seconds) { _, newValue in
                if Double(newValue) > displayed {
                    withAnimation(.easeOut(duration: 0.9)) {
                        displayed = Double(newValue)
                    }
                } else {
                    displayed = Double(newValue)
                }
            }
    }
}

/// Double 값을 보간하며 매 프레임 `goldTimeDurationText` 규칙으로 포맷해 카운트업처럼 보이게 한다.
private struct AnimatableDurationText: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        let secs = Int(value.rounded())
        Text(secs <= 0 ? String(localized: "home.bill.zero") : String(localized: "home.bill.total \(goldTimeDurationText(seconds: secs))"))
    }
}
