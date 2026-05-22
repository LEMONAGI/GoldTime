
import Foundation

final class AuthorizationRepositoryImpl: AuthorizationRepository {
    private let service: AuthorizationService

    init(service: AuthorizationService = .shared) {
        self.service = service
    }

    var isAuthorized: Bool { service.isAuthorized }

    func refresh() { service.refresh() }

    func request() async throws { try await service.request() }

    func settledIsAuthorized() async -> Bool { await service.settledIsAuthorized() }

    func observeAuthorizationChanges(_ handler: @escaping AuthorizationChangeHandler) -> AuthorizationObservation {
        service.observeAuthorizationChanges(handler)
    }
}
