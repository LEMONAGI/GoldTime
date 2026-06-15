
import Foundation

@MainActor
final class AppDIContainer {

    // MARK: - Core (싱글톤)
    private let authorizationService = AuthorizationService.shared
    private let rewardedAdService = RewardedAdService.shared

    // MARK: - Data Layer
    private lazy var groupRepository: any GroupRepository = GroupRepositoryImpl()
    private lazy var shieldRepository: any ShieldRepository = ShieldRepositoryImpl()
    private lazy var statsRepository: any StatsRepository = StatsRepositoryImpl()
    private lazy var screenTimeRepository: any ScreenTimeRepository = ScreenTimeRepositoryImpl()
    private lazy var authorizationRepository: any AuthorizationRepository =
        AuthorizationRepositoryImpl(service: authorizationService)
    private lazy var notificationRepository: any NotificationRepository = NotificationRepositoryImpl()
    private lazy var adRepository: any AdRepository = AdRepositoryImpl(service: rewardedAdService)
    private lazy var analyticsRepository: any AnalyticsRepository = AnalyticsRepositoryImpl()

    // MARK: - UseCase 팩토리

    func makeAuthorizeUseCase() -> AuthorizeUseCase {
        AuthorizeUseCase(
            authRepository: authorizationRepository,
            notificationRepository: notificationRepository
        )
    }

    func makeManageGroupsUseCase() -> ManageGroupsUseCase {
        ManageGroupsUseCase(
            groupRepository: groupRepository,
            screenTimeRepository: screenTimeRepository
        )
    }

    func makeSyncProtectionUseCase() -> SyncProtectionUseCase {
        SyncProtectionUseCase(
            groupRepository: groupRepository,
            screenTimeRepository: screenTimeRepository
        )
    }

    func makeLoadDashboardUseCase() -> LoadDashboardUseCase {
        LoadDashboardUseCase(
            shieldRepository: shieldRepository,
            statsRepository: statsRepository,
            screenTimeRepository: screenTimeRepository
        )
    }

    func makeExtendGroupUseCase() -> ExtendGroupUseCase {
        ExtendGroupUseCase(
            shieldRepository: shieldRepository,
            screenTimeRepository: screenTimeRepository
        )
    }

    func makeManageSettingsUseCase() -> ManageSettingsUseCase {
        ManageSettingsUseCase(
            authRepository: authorizationRepository,
            notificationRepository: notificationRepository
        )
    }

    // MARK: - ViewModel 팩토리

    func makeAppLifecycleViewModel() -> AppLifecycleViewModel {
        AppLifecycleViewModel(
            authorizeUseCase: makeAuthorizeUseCase(),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            shieldRepository: shieldRepository,
            analyticsRepository: analyticsRepository
        )
    }

    func makeContentViewModel() -> ContentViewModel {
        ContentViewModel(
            manageGroupsUseCase: makeManageGroupsUseCase(),
            syncProtectionUseCase: makeSyncProtectionUseCase(),
            loadDashboardUseCase: makeLoadDashboardUseCase(),
            authorizeUseCase: makeAuthorizeUseCase(),
            analyticsRepository: analyticsRepository
        )
    }

    func makeLockOptionsViewModel() -> LockOptionsViewModel {
        LockOptionsViewModel(
            extendGroupUseCase: makeExtendGroupUseCase(),
            analyticsRepository: analyticsRepository
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(manageSettingsUseCase: makeManageSettingsUseCase())
    }

    func makeOnboardingViewModel(onAuthorized: @escaping () -> Void) -> OnboardingViewModel {
        OnboardingViewModel(
            authorizeUseCase: makeAuthorizeUseCase(),
            analyticsRepository: analyticsRepository,
            onAuthorized: onAuthorized
        )
    }

    func makeRewardedAdViewModel(
        placement: RewardedAdPlacement,
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> RewardedAdViewModel {
        RewardedAdViewModel(
            placement: placement,
            adRepository: adRepository,
            onComplete: onComplete,
            onCancel: onCancel
        )
    }
}
