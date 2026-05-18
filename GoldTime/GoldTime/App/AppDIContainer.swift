
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

    // MARK: - ViewModel 팩토리

    func makeAppLifecycleViewModel() -> AppLifecycleViewModel {
        AppLifecycleViewModel(
            store: nil,
            screenTimeManager: nil,
            authorization: nil
        )
    }

    func makeContentViewModel() -> ContentViewModel {
        ContentViewModel(
            store: nil,
            screenTimeManager: nil,
            authorization: nil
        )
    }

    func makeLockOptionsViewModel() -> LockOptionsViewModel {
        LockOptionsViewModel(
            store: nil,
            screenTimeManager: nil
        )
    }

    func makeOnboardingViewModel(onAuthorized: @escaping () -> Void) -> OnboardingViewModel {
        OnboardingViewModel(
            authorization: nil,
            notificationAuthorizer: nil,
            onAuthorized: onAuthorized
        )
    }

    func makeRewardedAdViewModel(
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> RewardedAdViewModel {
        RewardedAdViewModel(
            adProvider: nil,
            onComplete: onComplete,
            onCancel: onCancel
        )
    }
}
