//
//  AuthorizationService.swift
//  GoldTime
//
//  Family Controls 권한 요청 및 상태 조회.
//

import FamilyControls
import Foundation

@Observable
final class AuthorizationService {
    static let shared = AuthorizationService()

    private(set) var isAuthorized: Bool = false
    private var authorizationChangeHandlers: [UUID: AuthorizationChangeHandler] = [:]

    private init() {
        refresh()
    }

    func refresh() {
        setAuthorized(AuthorizationCenter.shared.authorizationStatus == .approved)
    }

    func request() async throws {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            setAuthorized(true)
        } catch {
            setAuthorized(false)
            throw error
        }
    }

    func observeAuthorizationChanges(_ handler: @escaping AuthorizationChangeHandler) -> AuthorizationObservation {
        let id = UUID()
        authorizationChangeHandlers[id] = handler
        Task { @MainActor in handler(isAuthorized) }

        return AuthorizationObservation { [weak self] in
            self?.authorizationChangeHandlers[id] = nil
        }
    }

    private func setAuthorized(_ newValue: Bool) {
        guard isAuthorized != newValue else { return }
        isAuthorized = newValue
        notifyAuthorizationChangeHandlers(newValue)
    }

    private func notifyAuthorizationChangeHandlers(_ isAuthorized: Bool) {
        for handler in authorizationChangeHandlers.values {
            Task { @MainActor in handler(isAuthorized) }
        }
    }
}
