
//
//  OnboardingViewModel.swift
//  GoldTime
//

import Foundation

enum OnboardingStep: String {
    case intro
    case screenTimePermission
    case notificationPermission
    case trackingPermission
    case completion
}

@MainActor
@Observable
final class OnboardingViewModel {
    /// 온보딩 진행 단계 저장 키. 앱을 껐다 켜도 진행하던 단계로 복원하기 위해 사용한다.
    static let savedStepKey = "onboardingCurrentStep"
    static let hasLoggedEntryKey = "hasLoggedOnboardingEntered"
    static let hasLoggedCompletionKey = "hasLoggedOnboardingCompleted"

    // 단계가 바뀔 때마다 저장한다. init의 첫 할당에는 didSet이 호출되지 않으므로
    // 복원된(또는 시작) 단계는 불필요하게 다시 쓰지 않는다.
    var currentStep: OnboardingStep {
        didSet {
            userDefaults.set(currentStep.rawValue, forKey: Self.savedStepKey)
        }
    }
    var errorMessage: String?
    var isRequesting = false

    private let authorizeUseCase: AuthorizeUseCase
    private let analyticsRepository: any AnalyticsRepository
    private let onAuthorized: () -> Void
    private let userDefaults: UserDefaults

    init(
        authorizeUseCase: AuthorizeUseCase? = nil,
        analyticsRepository: (any AnalyticsRepository)? = nil,
        startStep: OnboardingStep = .intro,
        userDefaults: UserDefaults = .standard,
        onAuthorized: @escaping () -> Void
    ) {
        self.authorizeUseCase = authorizeUseCase ?? AuthorizeUseCase(
            authRepository: AuthorizationRepositoryImpl(),
            notificationRepository: NotificationRepositoryImpl()
        )
        self.analyticsRepository = analyticsRepository ?? AnalyticsRepositoryImpl()
        self.currentStep = startStep
        self.userDefaults = userDefaults
        self.onAuthorized = onAuthorized
    }

    func advance() {
        currentStep = .screenTimePermission
    }

    /// SwiftUI View 재생성·중간 단계 복원에서 진입 수가 부풀지 않도록 설치당 1회만 보낸다.
    func recordEntryIfNeeded() {
        guard !userDefaults.bool(forKey: Self.hasLoggedEntryKey) else { return }
        userDefaults.set(true, forKey: Self.hasLoggedEntryKey)
        analyticsRepository.log(.onboardingEntered)
    }

    func requestScreenTime() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await authorizeUseCase.requestScreenTime()
        } catch {
            errorMessage = String(localized: "onboarding.error.screenTime")
            return
        }
        if authorizeUseCase.isAuthorized {
            errorMessage = nil
            currentStep = .notificationPermission
        } else {
            errorMessage = String(localized: "onboarding.error.screenTime")
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
        await ConsentService.shared.requestConsentAndBeginAdInitialization()
        currentStep = .completion
    }

    func complete() {
        if !userDefaults.bool(forKey: Self.hasLoggedCompletionKey) {
            userDefaults.set(true, forKey: Self.hasLoggedCompletionKey)
            analyticsRepository.log(.onboardingCompleted)
        }
        // 온보딩을 끝까지 마쳤으므로 저장된 진행 단계를 정리한다.
        userDefaults.removeObject(forKey: Self.savedStepKey)
        onAuthorized()
    }
}
