
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

    private let authorizeUseCase: AuthorizeUseCase
    private let onAuthorized: () -> Void

    init(
        authorizeUseCase: AuthorizeUseCase? = nil,
        onAuthorized: @escaping () -> Void
    ) {
        self.authorizeUseCase = authorizeUseCase ?? AuthorizeUseCase(
            authRepository: AuthorizationRepositoryImpl(),
            notificationRepository: NotificationRepositoryImpl()
        )
        self.onAuthorized = onAuthorized
    }

    func requestAuthorization() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            try await authorizeUseCase.requestAll()
            if authorizeUseCase.isAuthorized {
                onAuthorized()
            } else {
                errorMessage = "권한이 필요해요. 설정에서 스크린타임 권한을 허용해주세요."
            }
        } catch {
            errorMessage = "권한 요청 실패: \(error.localizedDescription)"
        }
    }
}
