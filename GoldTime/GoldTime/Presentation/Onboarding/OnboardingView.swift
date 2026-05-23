//
//  OnboardingView.swift
//  GoldTime
//
//  최초 실행 시 권한 요청 4단계 흐름 화면.
//

import SwiftUI

private enum OnboardingPermissionType { case screenTime, notification }

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
            step: 0,
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
            step: 1,
            icon: "🔒",
            title: "스크린타임 권한",
            description: "앱 사용 시간을 추적하고\n한도를 초과하면 앱을 잠그기 위해\n스크린타임 접근 권한이 필요해요.",
            permissionType: .screenTime,
            errorMessage: viewModel.errorMessage,
            buttonTitle: viewModel.isRequesting ? "요청 중..." : "스크린타임 허용하기",
            isLoading: viewModel.isRequesting
        ) {
            Task { await viewModel.requestScreenTime() }
        }
    }

    private var notificationView: some View {
        OnboardingStepView(
            step: 2,
            icon: "🔔",
            title: "알림 권한",
            description: "한도에 가까워지면 알림으로 알려드려요.\n알림을 허용해야 앱을 사용할 수 있어요.",
            permissionType: .notification,
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
            step: 3,
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

// MARK: - Step View

private struct OnboardingStepView: View {
    @Environment(\.openURL) private var openURL

    let step: Int
    let icon: String
    let title: String
    let description: String
    var permissionType: OnboardingPermissionType? = nil
    let errorMessage: String?
    let buttonTitle: String
    let isLoading: Bool
    var settingsButtonVisible: Bool = false
    let action: () -> Void

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                StepDotIndicator(currentStep: step)
                    .padding(.top, 20)

                Spacer()

                VStack(spacing: 20) {
                    iconView
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(description)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                if let type = permissionType {
                    PermissionPreviewCard(type: type)
                        .padding(.top, 32)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 12) {
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
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(Color.accent.opacity(0.15))
                .frame(width: 100, height: 100)
            Text(icon)
                .font(.system(size: 52))
        }
    }
}

// MARK: - Step Dot Indicator

private struct StepDotIndicator: View {
    let currentStep: Int
    private let totalSteps = 4

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Color.accent : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Permission Preview Card

private struct PermissionPreviewCard: View {
    let type: OnboardingPermissionType

    private var dialogTitle: String {
        switch type {
        case .screenTime: "스크린타임 접근 허용"
        case .notification: "알림을 보내도 됩니까?"
        }
    }

    private var dialogMessage: String {
        switch type {
        case .screenTime: "앱 사용 시간을 추적하고 한도를 관리합니다."
        case .notification: "GoldTime이 알림을 보내드립니다."
        }
    }

    var body: some View {
        switch type {
        case .screenTime:
            screenTimeCard
        case .notification:
            notificationCard
        }
    }

    private var screenTimeNote: some View {
        Label("이 권한을 허용해야 앱을 사용할 수 있어요", systemImage: "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
    }

    private var notificationNote: some View {
        Label("'시간 지정 요약에서 허용'이 아닌 '허용'을 선택해야 즉시 알림을 받을 수 있어요", systemImage: "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
    }

    private var screenTimeCard: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                Text(dialogTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(dialogMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 8) {
                    Text("계속")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("허용 안 함")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)
            }
            .cardContainer(padding: 16)

            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.accent)
                    Text("여기를 탭해요")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accent)
                }
                .frame(maxWidth: .infinity)
                Spacer()
                    .frame(maxWidth: .infinity)
            }

            screenTimeNote
        }
    }

    private var notificationCard: some View {
        VStack(spacing: 12) {

            VStack(spacing: 10) {
                Text(dialogTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(dialogMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    Text("허용")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("시간 지정 요약에서 허용")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("허용 안 함")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)
            }
            .cardContainer(padding: 16)

            notificationNote
        }
    }
}

#Preview("Intro") {
    OnboardingView(startStep: .intro) {}
}

#Preview("ScreenTime") {
    OnboardingView(startStep: .screenTimePermission) {}
}

#Preview("Notification") {
    OnboardingView(startStep: .notificationPermission) {}
}

#Preview("Completion") {
    OnboardingView(startStep: .completion) {}
}
