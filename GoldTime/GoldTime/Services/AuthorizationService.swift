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

    private init() {
        refresh()
    }

    func refresh() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func request() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        refresh()
    }
}
