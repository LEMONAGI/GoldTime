//
//  StrictLockBetaBanner.swift
//  GoldTime
//
//  홈 상단 "연장 불가 모드 베타 출시" 안내 배너. 탭하면 상위(ContentView)가 안내 시트를 띄운다.
//  첫 진입 때만 테두리가 금빛으로 회전 발광(`isGlowing`)해 시선을 끌고, 한 번 누르면 발광이
//  꺼지고 그룹 카드와 같은 연한 회색 배경만 남는다(안내를 다시 볼 수 있는 상시 진입점).
//
//  이 발광 테두리는 그룹 카드 행에서 제거된 `StrictLockGlowBorder`(2026-08-15)와 다른 맥락이다:
//  단일 배너 + 첫 탭 전까지만 발광이라 "적용 그룹 수만큼 동시 회전·발광" 우려가 없다. 회귀로
//  제거하지 말 것(Presentation/CLAUDE.md 연장 불가 표기 계약 ⑥ 참조).
//

import SwiftUI

struct StrictLockBetaBanner: View {
    /// 첫 탭 전까지 true — 금빛 회전 발광. 탭 후에는 false로 내려와 연한 회색 배경만 남는다.
    var isGlowing: Bool
    let onTap: () -> Void

    private let cornerRadius: CGFloat = 16

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "megaphone.fill")
                .font(.headline)
                .foregroundStyle(Color.accent)

            Text("home.strictLockBeta.banner")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 발광 중엔 accent 틴트로 온기를 주고, 탭 후엔 그룹 카드와 같은 연한 회색 배경만 남긴다.
        .background(isGlowing ? Color.accent.opacity(0.08) : Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            if isGlowing {
                GoldGlowBorder(cornerRadius: cornerRadius)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// 밝은 금빛 호(arc)가 테두리를 매끄럽게 도는 발광 오버레이. 각도 그라디언트를 **통째로**
/// `rotationEffect`로 돌려(그라디언트 각도를 매 프레임 재계산하는 대신 GPU 레이어 변환) 끊김 없이
/// 회전한다. "손쉬운 사용 > 동작 줄이기"가 켜지면 회전을 멈추고 정적 금빛 테두리만 남긴다.
/// 탭·보이스오버에 잡히지 않게 히트 테스트·접근성에서 제외한다.
private struct GoldGlowBorder: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    /// 한 바퀴 도는 데 걸리는 시간(초). 값이 클수록 느리게 돈다.
    private let period: Double = 3.0

    var body: some View {
        Group {
            if reduceMotion {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.accent.opacity(0.6), lineWidth: 2)
                    .shadow(color: Color.accent.opacity(0.5), radius: 5)
            } else {
                ZStack {
                    ring.blur(radius: 7)  // 후광
                    ring                  // 선명한 테두리
                }
                .shadow(color: Color.accent.opacity(0.55), radius: 4)
                .onAppear {
                    withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                        angle = 360
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 밝은 금빛 호가 도는 링. 큰 정사각형 그라디언트를 배너 중심에 두고 통째로 회전시켜(어느
    /// 각도에서도 테두리를 덮게) 테두리 모양 마스크로 오려낸다.
    private var ring: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 2
            AngularGradient(
                gradient: Gradient(colors: [
                    Color.accent.opacity(0.12),
                    Color.accent.opacity(0.35),
                    Color.accent,
                    Color.accent.opacity(0.35),
                    Color.accent.opacity(0.12),
                ]),
                center: .center
            )
            .frame(width: side, height: side)
            .rotationEffect(.degrees(angle))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .mask {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(lineWidth: 2)
        }
    }
}

#Preview("발광 O") {
    StrictLockBetaBanner(isGlowing: true) {}
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("발광 X (탭 후)") {
    StrictLockBetaBanner(isGlowing: false) {}
        .padding()
        .background(Color(.systemGroupedBackground))
}

#Preview("발광 O — EN") {
    StrictLockBetaBanner(isGlowing: true) {}
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(\.locale, .init(identifier: "en"))
}

#Preview("발광 O — JA") {
    StrictLockBetaBanner(isGlowing: true) {}
        .padding()
        .background(Color(.systemGroupedBackground))
        .environment(\.locale, .init(identifier: "ja"))
}
