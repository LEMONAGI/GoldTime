//
//  OnboardingView.swift
//  GoldTime
//
//  최초 실행 시 권한 요청 4단계 흐름 화면.
//

import SwiftUI

private enum OnboardingPermissionType { case screenTime, notification, tracking }

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
        case .trackingPermission:
            trackingView
        case .completion:
            completionView
        }
    }

    private var introView: some View {
        OnboardingStepView(
            step: 0,
            icon: "hourglass",
            title: "onboarding.intro.title",
            description: "onboarding.intro.description",
            errorMessage: nil,
            buttonTitle: "common.start",
            isLoading: false
        ) {
            viewModel.advance()
        }
    }

    private var screenTimeView: some View {
        OnboardingStepView(
            step: 1,
            icon: "lock.fill",
            title: "onboarding.screenTime.title",
            description: "onboarding.screenTime.description",
            permissionType: .screenTime,
            errorMessage: viewModel.errorMessage,
            buttonTitle: viewModel.isRequesting ? "common.requesting" : "onboarding.screenTime.button",
            isLoading: viewModel.isRequesting
        ) {
            Task { await viewModel.requestScreenTime() }
        }
    }

    private var notificationView: some View {
        OnboardingStepView(
            step: 2,
            icon: "bell.fill",
            title: "onboarding.notification.title",
            description: "onboarding.notification.description",
            permissionType: .notification,
            errorMessage: viewModel.errorMessage,
            buttonTitle: viewModel.isRequesting ? "common.requesting" : "onboarding.notification.button",
            isLoading: viewModel.isRequesting,
            settingsButtonVisible: viewModel.errorMessage != nil,
            skipTitle: "onboarding.notification.skip",
            skipAction: { viewModel.skipNotification() }
        ) {
            Task { await viewModel.requestNotification() }
        }
    }

    private var trackingView: some View {
        OnboardingStepView(
            step: 3,
            icon: "hand.raised.fill",
            title: "onboarding.tracking.title",
            description: "onboarding.tracking.description",
            permissionType: .tracking,
            errorMessage: nil,
            buttonTitle: viewModel.isRequesting ? "common.requesting" : "onboarding.tracking.button",
            isLoading: viewModel.isRequesting
        ) {
            Task { await viewModel.requestTracking() }
        }
    }

    private var completionView: some View {
        OnboardingStepView(
            step: 4,
            icon: "checkmark.circle.fill",
            title: "onboarding.completion.title",
            description: "onboarding.completion.description",
            errorMessage: nil,
            buttonTitle: "common.start",
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
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    var permissionType: OnboardingPermissionType? = nil
    let errorMessage: String?
    let buttonTitle: LocalizedStringKey
    let isLoading: Bool
    var settingsButtonVisible: Bool = false
    var skipTitle: LocalizedStringKey? = nil
    var skipAction: (() -> Void)? = nil
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
                        Button("common.openSettings") {
                            openURL(url)
                        }
                        .font(.subheadline)
                    }
                    Button(action: action) {
                        Text(buttonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GoldTimeButtonStyle(background: Color.accent, foreground: .black, cornerRadius: 16))
                    .disabled(isLoading)
                    .padding(.horizontal, 24)

                    if let skipTitle, let skipAction {
                        Button(skipTitle, action: skipAction)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .disabled(isLoading)
                            .padding(.top, 4)
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(Color.accent.opacity(0.15))
                .frame(width: 100, height: 100)
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.accent)
        }
    }
}

// MARK: - Step Dot Indicator

private struct StepDotIndicator: View {
    let currentStep: Int
    private let totalSteps = 5

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

    private var dialogTitle: LocalizedStringKey {
        switch type {
        case .screenTime: "onboarding.dialog.screenTime.title"
        case .notification: "onboarding.dialog.notification.title"
        case .tracking: "onboarding.dialog.tracking.title"
        }
    }

    private var dialogMessage: LocalizedStringKey {
        switch type {
        case .screenTime: "onboarding.dialog.screenTime.message"
        case .notification: "onboarding.dialog.notification.message"
        case .tracking: "onboarding.dialog.tracking.message"
        }
    }

    var body: some View {
        switch type {
        case .screenTime:
            screenTimeCard
        case .notification:
            notificationCard
        case .tracking:
            trackingCard
        }
    }

    private var screenTimeNote: some View {
        Label("onboarding.note.screenTime", systemImage: "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var notificationNote: some View {
        Label("onboarding.note.notification", systemImage: "info.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trackingNote: some View {
        Label("onboarding.note.tracking", systemImage: "info.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
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
                    Text("onboarding.dialog.continue")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("onboarding.dialog.dontAllow")
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
                    Text("onboarding.dialog.tapHere")
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
                    Text("onboarding.dialog.allow")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("onboarding.dialog.allowInSummary")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("onboarding.dialog.dontAllow")
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

    private var trackingCard: some View {
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
                    Text("onboarding.dialog.noTracking")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text("onboarding.dialog.allowTracking")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)
            }
            .cardContainer(padding: 16)

            trackingNote
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
