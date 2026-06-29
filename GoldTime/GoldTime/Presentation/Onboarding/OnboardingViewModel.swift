
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

    // 단계가 바뀔 때마다 저장한다. init의 첫 할당에는 didSet이 호출되지 않으므로
    // 복원된(또는 시작) 단계는 불필요하게 다시 쓰지 않는다.
    var currentStep: OnboardingStep {
        didSet {
            userDefaults.set(currentStep.rawValue, forKey: Self.savedStepKey)
            // init의 첫 할당에는 didSet이 호출되지 않으므로(.intro=진입은 first_open으로 대체)
            // 여기 도착하는 건 사용자가 단계를 넘긴 실제 전환뿐 → 온보딩 드롭오프 퍼널의 단계 조회.
            analyticsRepository.log(.onboardingStepView(step: currentStep.rawValue))
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

    func requestScreenTime() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await authorizeUseCase.requestScreenTime()
        } catch {
            analyticsRepository.log(.authorizationResult(granted: false))
            errorMessage = String(localized: "onboarding.error.screenTime")
            return
        }
        if authorizeUseCase.isAuthorized {
            analyticsRepository.log(.authorizationResult(granted: true))
            errorMessage = nil
            currentStep = .notificationPermission
        } else {
            analyticsRepository.log(.authorizationResult(granted: false))
            errorMessage = String(localized: "onboarding.error.screenTime")
        }
    }

    func requestNotification() async {
        isRequesting = true
        defer { isRequesting = false }
        // 알림은 선택 권한이므로 허용/거부 결과와 관계없이 다음 단계로 진행한다.
        let state = await authorizeUseCase.requestNotification()
        analyticsRepository.log(.notificationPermissionResult(granted: state == .authorized))
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
        // 온보딩을 끝까지 마쳤으므로 저장된 진행 단계를 정리한다.
        userDefaults.removeObject(forKey: Self.savedStepKey)
        onAuthorized()
    }
}
