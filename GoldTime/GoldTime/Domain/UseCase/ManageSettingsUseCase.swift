import Foundation

final class ManageSettingsUseCase {
    private let authRepository: any AuthorizationRepository
    private let notificationRepository: any NotificationRepository

    init(
        authRepository: any AuthorizationRepository,
        notificationRepository: any NotificationRepository
    ) {
        self.authRepository = authRepository
        self.notificationRepository = notificationRepository
    }

    var isScreenTimeAuthorized: Bool {
        authRepository.isAuthorized
    }

    func refreshScreenTimeAuthorization() -> Bool {
        authRepository.refresh()
        return authRepository.isAuthorized
    }

    func requestScreenTimeAuthorization() async throws -> Bool {
        try await authRepository.request()
        authRepository.refresh()
        return authRepository.isAuthorized
    }

    func notificationAuthorizationState() async -> NotificationPermissionState {
        await notificationRepository.authorizationState()
    }

    func requestNotificationAuthorizationIfNeeded() async -> NotificationPermissionState {
        await notificationRepository.requestAuthorizationIfNeeded()
    }
}
