//
//  OnboardingViewModel.swift
//  GoldTime
//

import Foundation

@MainActor
@Observable
final class OnboardingViewModel {
    var errorMessage: String?
    var isRequesting = false

    private let authorization: any AuthorizationProviding
    private let notificationAuthorizer: any NotificationAuthorizing
    private let onAuthorized: () -> Void

    init(
        authorization: (any AuthorizationProviding)? = nil,
        notificationAuthorizer: (any NotificationAuthorizing)? = nil,
        onAuthorized: @escaping () -> Void
    ) {
        self.authorization = authorization ?? AuthorizationService.shared
        self.notificationAuthorizer = notificationAuthorizer ?? NotificationServiceAdapter()
        self.onAuthorized = onAuthorized
    }

    func requestAuthorization() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await authorization.request()
            await notificationAuthorizer.requestAuthorizationIfNeeded()
            if authorization.isAuthorized {
                onAuthorized()
            } else {
                errorMessage = "권한이 필요해요. 설정에서 스크린타임 권한을 허용해주세요."
            }
        } catch {
            errorMessage = "권한 요청 실패: \(error.localizedDescription)"
        }
    }
}
