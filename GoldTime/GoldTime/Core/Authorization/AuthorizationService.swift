//
//  AuthorizationService.swift
//  GoldTime
//
//  Family Controls 권한 요청 및 상태 조회.
//

internal import Combine
import FamilyControls
import Foundation

@Observable
final class AuthorizationService {
    static let shared = AuthorizationService()

    private(set) var isAuthorized: Bool = false
    private var cancellable: AnyCancellable?
    private var authorizationChangeHandlers: [UUID: AuthorizationChangeHandler] = [:]

    private init() {
        refresh()
        // FamilyControls 상태를 디스크에서 비동기 로드하므로, 변경 알림을 구독해 반응적으로 갱신
        cancellable = AuthorizationCenter.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange는 변경 전에 발생하므로 한 틱 뒤에 읽음
                DispatchQueue.main.async { self?.refresh() }
            }
    }

    func refresh() {
        let newValue = AuthorizationCenter.shared.authorizationStatus == .approved
        guard isAuthorized != newValue else { return }
        isAuthorized = newValue
        notifyAuthorizationChangeHandlers(newValue)
    }

    func request() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        refresh()
    }

    func settledIsAuthorized() async -> Bool {
        guard AuthorizationCenter.shared.authorizationStatus == .notDetermined else {
            return AuthorizationCenter.shared.authorizationStatus == .approved
        }
        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            var resumed = false
            let resume: (Bool) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
                cancellable?.cancel()
                cancellable = nil
            }
            cancellable = AuthorizationCenter.shared.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    DispatchQueue.main.async {
                        resume(AuthorizationCenter.shared.authorizationStatus == .approved)
                    }
                }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                resume(AuthorizationCenter.shared.authorizationStatus == .approved)
            }
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

    private func notifyAuthorizationChangeHandlers(_ isAuthorized: Bool) {
        for handler in authorizationChangeHandlers.values {
            Task { @MainActor in handler(isAuthorized) }
        }
    }
}
