
import Foundation

typealias AuthorizationChangeHandler = @MainActor (Bool) -> Void

final class AuthorizationObservation {
    private let onCancel: () -> Void
    private var isCancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }

    deinit {
        cancel()
    }
}

protocol AuthorizationRepository {
    var isAuthorized: Bool { get }
    func refresh()
    func request() async throws
    func settledIsAuthorized() async -> Bool
    func observeAuthorizationChanges(_ handler: @escaping AuthorizationChangeHandler) -> AuthorizationObservation
}
