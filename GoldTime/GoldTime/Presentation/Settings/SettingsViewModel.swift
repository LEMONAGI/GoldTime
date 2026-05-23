//
//  SettingsViewModel.swift
//  GoldTime
//

import Foundation

struct SettingsAlertMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func == (lhs: SettingsAlertMessage, rhs: SettingsAlertMessage) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    var isScreenTimeAuthorized: Bool
    var notificationPermissionState: NotificationPermissionState = .unknown
    var isRequestingScreenTimeAuthorization = false
    var isRequestingNotificationAuthorization = false
    var alertMessage: SettingsAlertMessage?
    var weekStartDay: Int = SharedStore.weekStartDay {
        didSet { SharedStore.weekStartDay = weekStartDay }
    }

    private let manageSettingsUseCase: ManageSettingsUseCase

    init(manageSettingsUseCase: ManageSettingsUseCase? = nil) {
        let authRepo = AuthorizationRepositoryImpl()
        let notifRepo = NotificationRepositoryImpl()
        self.manageSettingsUseCase = manageSettingsUseCase ?? ManageSettingsUseCase(
            authRepository: authRepo,
            notificationRepository: notifRepo
        )
        isScreenTimeAuthorized = self.manageSettingsUseCase.isScreenTimeAuthorized
    }

    func loadState() async {
        isScreenTimeAuthorized = manageSettingsUseCase.refreshScreenTimeAuthorization()
        notificationPermissionState = await manageSettingsUseCase.notificationAuthorizationState()
    }

    func requestScreenTimeAuthorization() async {
        isRequestingScreenTimeAuthorization = true
        defer { isRequestingScreenTimeAuthorization = false }

        do {
            isScreenTimeAuthorized = try await manageSettingsUseCase.requestScreenTimeAuthorization()
            if !isScreenTimeAuthorized {
                alertMessage = SettingsAlertMessage(
                    title: "스크린 타임 권한 필요",
                    message: "GoldTime이 앱 한도를 적용하려면 스크린 타임 권한이 필요해요."
                )
            }
        } catch {
            alertMessage = SettingsAlertMessage(
                title: "권한 요청 실패",
                message: error.localizedDescription
            )
        }
    }

    func requestNotificationAuthorization() async {
        isRequestingNotificationAuthorization = true
        defer { isRequestingNotificationAuthorization = false }

        notificationPermissionState = await manageSettingsUseCase.requestNotificationAuthorizationIfNeeded()
    }
}
