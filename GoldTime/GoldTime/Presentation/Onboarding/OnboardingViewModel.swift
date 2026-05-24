
//
//  OnboardingViewModel.swift
//  GoldTime
//

import Foundation

enum OnboardingStep {
    case intro
    case screenTimePermission
    case notificationPermission
    case completion
}

@MainActor
@Observable
final class OnboardingViewModel {
    var currentStep: OnboardingStep
    var errorMessage: String?
    var isRequesting = false

    private let authorizeUseCase: AuthorizeUseCase
    private let onAuthorized: () -> Void

    init(
        authorizeUseCase: AuthorizeUseCase? = nil,
        startStep: OnboardingStep = .intro,
        onAuthorized: @escaping () -> Void
    ) {
        self.authorizeUseCase = authorizeUseCase ?? AuthorizeUseCase(
            authRepository: AuthorizationRepositoryImpl(),
            notificationRepository: NotificationRepositoryImpl()
        )
        self.currentStep = startStep
        self.onAuthorized = onAuthorized
    }

    func advance() {
        currentStep = .screenTimePermission
    }

    func requestScreenTime() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await authorizeUseCase.requestScreenTime()
        } catch {
            errorMessage = "스크린타임 권한이 필요해요. 다시 한 번 버튼을 눌러 권한을 허용해주세요."
            return
        }
        if authorizeUseCase.isAuthorized {
            errorMessage = nil
            currentStep = .notificationPermission
        } else {
            errorMessage = "스크린타임 권한이 필요해요. 다시 한 번 버튼을 눌러 권한을 허용해주세요."
        }
    }

    func requestNotification() async {
        isRequesting = true
        defer { isRequesting = false }
        let state = await authorizeUseCase.requestNotification()
        if [NotificationPermissionState.authorized, .provisional, .ephemeral].contains(state) {
            errorMessage = nil
            currentStep = .completion
        } else {
            errorMessage = "알림을 허용해야 앱을 시작할 수 있어요. iOS 설정 > GoldTime에서 알림을 켜주세요."
        }
    }

    func complete() {
        onAuthorized()
    }
}
