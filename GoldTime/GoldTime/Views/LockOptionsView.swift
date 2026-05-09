//
//  LockOptionsView.swift
//  GoldTime
//
//  쉴드가 활성화된 상태에서 앱 진입 시 표시되는 3-옵션 모달.
//

import SwiftUI

struct LockOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oneMinuteRemaining: Int = SharedStore.oneMinuteRemaining
    @State private var showAdMock = false
    @State private var infoMessage: String?

    private let shieldMessages = [
        "오늘 한도를 다 썼어요.",
        "여기서 멈추면 광고는 없습니다.",
        "더 쓰려면 광고가 필요해요.",
        "잠깐 쉬어갈 시간이에요.",
        "멈추거나, 광고를 보거나."
    ]
    @State private var headerMessage: String = ""

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("💰").font(.system(size: 56))
                Text("시간이 금이다")
                    .font(.title.bold())
                Text(headerMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)
            .onAppear {
                headerMessage = shieldMessages.randomElement() ?? "오늘 한도를 다 썼어요."
            }

            Spacer()

            VStack(spacing: 12) {
                optionButton(
                    title: "1분만 더 쓰기",
                    subtitle: oneMinuteRemaining > 0
                        ? "오늘 \(oneMinuteRemaining)번 남았어요"
                        : "오늘은 더 사용할 수 없어요",
                    background: oneMinuteRemaining > 0 ? Color.goldPrimary : Color.gray.opacity(0.3),
                    foreground: oneMinuteRemaining > 0 ? .black : .gray,
                    enabled: oneMinuteRemaining > 0,
                    action: tapOneMinute
                )

                optionButton(
                    title: "광고 보고 15분 더 쓰기",
                    subtitle: "광고가 끝나면 잠금이 풀려요",
                    background: Color.goldPrimary,
                    foreground: .black,
                    enabled: true,
                    action: { showAdMock = true }
                )

                optionButton(
                    title: "그만 쓰기",
                    subtitle: "잠금을 유지하고 돌아갑니다",
                    background: Color.gray.opacity(0.2),
                    foreground: .primary,
                    enabled: true,
                    action: { dismiss() }
                )
            }
            .padding(.horizontal, 20)

            if let infoMessage {
                Text(infoMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .fullScreenCover(isPresented: $showAdMock) {
            AdMockView(
                onComplete: {
                    showAdMock = false
                    ScreenTimeManager.consumeAdReward()
                    dismiss()
                },
                onCancel: {
                    showAdMock = false
                }
            )
        }
        .interactiveDismissDisabled()
    }

    private func tapOneMinute() {
        if ScreenTimeManager.consumeOneMinute() {
            dismiss()
        } else {
            infoMessage = "오늘 1분 연장은 모두 사용했어요. 광고를 보거나 잠금을 유지할 수 있어요."
            oneMinuteRemaining = 0
        }
    }

    @ViewBuilder
    private func optionButton(
        title: String,
        subtitle: String,
        background: Color,
        foreground: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled)
    }
}
