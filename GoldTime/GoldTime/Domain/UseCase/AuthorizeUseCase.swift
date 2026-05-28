
import Foundation

final class AuthorizeUseCase {
    private let authRepository: any AuthorizationRepository
    private let notificationRepository: any NotificationRepository

    init(
        authRepository: any AuthorizationRepository,
        notificationRepository: any NotificationRepository
    ) {
        self.authRepository = authRepository
        self.notificationRepository = notificationRepository
    }

    var isAuthorized: Bool { authRepository.isAuthorized }

    func refresh() { authRepository.refresh() }

    func observeAuthorizationChanges(_ handler: @escaping AuthorizationChangeHandler) -> AuthorizationObservation {
        authRepository.observeAuthorizationChanges(handler)
    }

    func requestAll() async throws {
        try await authRepository.request()
        _ = await notificationRepository.requestAuthorizationIfNeeded()
    }

    func requestScreenTime() async throws {
        try await authRepository.request()
    }

    func requestNotification() async -> NotificationPermissionState {
        await notificationRepository.requestAuthorizationIfNeeded()
    }

    func notificationState() async -> NotificationPermissionState {
        await notificationRepository.authorizationState()
    }
}
