
//
//  OnboardingViewModel.swift
//  GoldTime
//

import Foundation

enum OnboardingStep {
    case intro
    case screenTimePermission
    case notificationPermission
    case trackingPermission
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
        // 알림은 선택 권한이므로 허용/거부 결과와 관계없이 다음 단계로 진행한다.
        _ = await authorizeUseCase.requestNotification()
        errorMessage = nil
        currentStep = .trackingPermission
    }

    func skipNotification() {
        errorMessage = nil
        currentStep = .trackingPermission
    }

    func requestTracking() async {
        isRequesting = true
        defer { isRequesting = false }
        await ConsentService.shared.requestConsentAndInitialize()
        currentStep = .completion
    }

    func complete() {
        onAuthorized()
    }
}
