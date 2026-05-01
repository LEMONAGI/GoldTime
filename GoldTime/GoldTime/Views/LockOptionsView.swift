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

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("⏳").font(.system(size: 56))
                Text("시간이 금이다")
                    .font(.title.bold())
                Text("오늘 한도를 다 썼어요.\n어떻게 할까요?")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 32)

            Spacer()

            VStack(spacing: 12) {
                optionButton(
                    title: "딱 1분만요.. 진짜로..",
                    subtitle: oneMinuteRemaining > 0
                        ? "오늘 \(oneMinuteRemaining)회 남음"
                        : "오늘 다 썼어요",
                    background: oneMinuteRemaining > 0 ? Color.yellow : Color.gray.opacity(0.3),
                    foreground: oneMinuteRemaining > 0 ? .black : .gray,
                    enabled: oneMinuteRemaining > 0,
                    action: tapOneMinute
                )

                optionButton(
                    title: "광고보고 더 할게요",
                    subtitle: "광고 시청 후 15분 연장",
                    background: Color.blue,
                    foreground: .white,
                    enabled: true,
                    action: { showAdMock = true }
                )

                optionButton(
                    title: "... 잘 참았어요",
                    subtitle: "잠금을 유지합니다",
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
                    ScreenTimeManager.releaseShield(forSeconds: 15 * 60)
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
            infoMessage = "오늘은 더 이상 1분 연장이 불가능해요."
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
