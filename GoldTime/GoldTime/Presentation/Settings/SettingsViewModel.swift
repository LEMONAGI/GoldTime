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
    /// 권한은 허용됐지만 "시간 지정 요약"에 묶여 알림이 지연되는 상태.
    var isNotificationDeferredBySummary = false
    var isRequestingScreenTimeAuthorization = false
    var isRequestingNotificationAuthorization = false
    var isDailyMorningNotificationEnabled: Bool
    var alertMessage: SettingsAlertMessage?
    var weekStartDay: Int = SharedStore.weekStartDay {
        didSet { SharedStore.weekStartDay = weekStartDay }
    }

    /// 개인정보 처리방침 URL. 시스템 언어(ko/en/ja)에 맞는 Notion 페이지를 로컬라이징으로 선택한다.
    /// 같은 주소를 App Store Connect 앱 개인정보 URL에도 쓴다.
    var privacyPolicyURL: URL? {
        URL(string: String(localized: "settings.privacy.policy.url"))
    }

    /// EEA/UK 등에서만 "광고/개인정보 설정" 행을 노출한다. 그 외 지역은 false라 행이 숨겨진다.
    var isPrivacyOptionsAvailable: Bool {
        ConsentService.shared.isPrivacyOptionsRequired
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
        isDailyMorningNotificationEnabled = self.manageSettingsUseCase.isDailyMorningNotificationEnabled
    }

    func setDailyMorningNotificationEnabled(_ enabled: Bool) {
        isDailyMorningNotificationEnabled = enabled
        manageSettingsUseCase.setDailyMorningNotificationEnabled(enabled)
    }

    func loadState() async {
        isScreenTimeAuthorized = manageSettingsUseCase.refreshScreenTimeAuthorization()
        notificationPermissionState = await manageSettingsUseCase.notificationAuthorizationState()
        isNotificationDeferredBySummary = await manageSettingsUseCase.isNotificationDeferredByScheduledSummary()
        isDailyMorningNotificationEnabled = manageSettingsUseCase.isDailyMorningNotificationEnabled
    }

    func requestScreenTimeAuthorization() async {
        isRequestingScreenTimeAuthorization = true
        defer { isRequestingScreenTimeAuthorization = false }

        do {
            isScreenTimeAuthorized = try await manageSettingsUseCase.requestScreenTimeAuthorization()
            if !isScreenTimeAuthorized {
                alertMessage = SettingsAlertMessage(
                    title: String(localized: "settings.alert.screenTime.title"),
                    message: String(localized: "settings.alert.screenTime.message")
                )
            }
        } catch {
            alertMessage = SettingsAlertMessage(
                title: String(localized: "settings.alert.requestFailed.title"),
                message: error.localizedDescription
            )
        }
    }

    func requestNotificationAuthorization() async {
        isRequestingNotificationAuthorization = true
        defer { isRequestingNotificationAuthorization = false }

        notificationPermissionState = await manageSettingsUseCase.requestNotificationAuthorizationIfNeeded()
        isNotificationDeferredBySummary = await manageSettingsUseCase.isNotificationDeferredByScheduledSummary()
    }

    /// 사용자가 광고 개인화 동의를 변경/철회할 수 있도록 UMP privacy options 폼을 띄운다.
    func presentPrivacyOptions() async {
        await ConsentService.shared.presentPrivacyOptions()
    }
}
