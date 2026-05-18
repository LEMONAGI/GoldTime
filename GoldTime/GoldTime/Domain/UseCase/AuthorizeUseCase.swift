
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

    func requestAll() async throws {
        try await authRepository.request()
        await notificationRepository.requestAuthorizationIfNeeded()
    }
}
