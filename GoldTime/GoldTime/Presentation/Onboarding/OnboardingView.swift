//
//  OnboardingView.swift
//  GoldTime
//
//  최초 실행 시 권한 요청 4단계 흐름 화면.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel: OnboardingViewModel

    init(startStep: OnboardingStep = .intro, onAuthorized: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(startStep: startStep, onAuthorized: onAuthorized))
    }

    var body: some View {
        switch viewModel.currentStep {
        case .intro:
            introView
        case .screenTimePermission:
            screenTimeView
        case .notificationPermission:
            notificationView
        case .completion:
            completionView
        }
    }

    private var introView: some View {
        OnboardingStepView(
            icon: "💰",
            title: "시간이 금이다",
            description: "한도를 넘기면 선택한 앱이 잠기고,\n더 쓰려면 광고를 봐야 해요.\n조금 불편하게 만들어두겠습니다.",
            errorMessage: nil,
            buttonTitle: "시작하기",
            isLoading: false
        ) {
            viewModel.advance()
        }
    }

    private var screenTimeView: some View {
        OnboardingStepView(
            icon: "🔒",
            title: "스크린타임 권한",
            description: "앱 사용 시간을 추적하고\n한도를 초과하면 앱을 잠그기 위해\n스크린타임 접근 권한이 필요해요.",
            errorMessage: viewModel.errorMessage,
            buttonTitle: viewModel.isRequesting ? "요청 중..." : "스크린타임 허용하기",
            isLoading: viewModel.isRequesting
        ) {
            Task { await viewModel.requestScreenTime() }
        }
    }

    private var notificationView: some View {
        OnboardingStepView(
            icon: "🔔",
            title: "알림 권한",
            description: "한도에 가까워지면 알림으로 알려드려요.\n알림을 허용해야 앱을 사용할 수 있어요.",
            errorMessage: viewModel.errorMessage,
            buttonTitle: viewModel.isRequesting ? "요청 중..." : "알림 허용하기",
            isLoading: viewModel.isRequesting,
            settingsButtonVisible: viewModel.errorMessage != nil
        ) {
            Task { await viewModel.requestNotification() }
        }
    }

    private var completionView: some View {
        OnboardingStepView(
            icon: "✅",
            title: "준비 완료!",
            description: "이제 시간의 가치를 느껴보세요.",
            errorMessage: nil,
            buttonTitle: "시작하기",
            isLoading: false
        ) {
            viewModel.complete()
        }
    }
}

private struct OnboardingStepView: View {
    @Environment(\.openURL) private var openURL

    let icon: String
    let title: String
    let description: String
    let errorMessage: String?
    let buttonTitle: String
    let isLoading: Bool
    var settingsButtonVisible: Bool = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(icon)
                .font(.system(size: 80))
            Text(title)
                .font(.largeTitle.bold())
            Text(description)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if settingsButtonVisible, let url = URL(string: "app-settings:") {
                Button("설정 열기") {
                    openURL(url)
                }
                .font(.subheadline)
            }
            Button(action: action) {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black, cornerRadius: 12))
            .disabled(isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
