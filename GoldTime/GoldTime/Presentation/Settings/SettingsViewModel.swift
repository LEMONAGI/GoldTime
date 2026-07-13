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
    var isUsageAlertEnabled: Bool
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

    /// 금고 모드 기능 사용 여부(기본 Off). Off면 그룹 카드에 금고 행이 아예 보이지 않는다.
    var isStrictLockEnabled: Bool

    /// 진행 중인 약정이 있으면 기능을 끌 수 없다(끄기로 우회 해제하는 구멍 차단).
    var canDisableStrictLock: Bool {
        !manageGroupsUseCase.hasActiveStrictLock()
    }

    private let manageSettingsUseCase: ManageSettingsUseCase
    private let manageGroupsUseCase: ManageGroupsUseCase

    init(
        manageSettingsUseCase: ManageSettingsUseCase? = nil,
        manageGroupsUseCase: ManageGroupsUseCase? = nil
    ) {
        let authRepo = AuthorizationRepositoryImpl()
        let notifRepo = NotificationRepositoryImpl()
        self.manageSettingsUseCase = manageSettingsUseCase ?? ManageSettingsUseCase(
            authRepository: authRepo,
            notificationRepository: notifRepo
        )
        self.manageGroupsUseCase = manageGroupsUseCase ?? ManageGroupsUseCase(
            groupRepository: GroupRepositoryImpl(),
            screenTimeRepository: ScreenTimeRepositoryImpl()
        )
        isScreenTimeAuthorized = self.manageSettingsUseCase.isScreenTimeAuthorized
        isDailyMorningNotificationEnabled = self.manageSettingsUseCase.isDailyMorningNotificationEnabled
        isUsageAlertEnabled = self.manageSettingsUseCase.isUsageAlertEnabled
        isStrictLockEnabled = self.manageGroupsUseCase.isStrictLockEnabled
    }

    /// 금고 모드 기능 토글. 약정 중인 그룹이 있으면 끄기가 거부되고(토글 원복) 사유를 안내한다.
    func setStrictLockEnabled(_ enabled: Bool) {
        guard manageGroupsUseCase.setStrictLockEnabled(enabled) else {
            isStrictLockEnabled = true   // 끄기 실패 → 켜진 상태 유지
            alertMessage = SettingsAlertMessage(
                title: String(localized: "settings.alert.strictLockInUse.title"),
                message: String(localized: "settings.alert.strictLockInUse.message")
            )
            return
        }
        isStrictLockEnabled = enabled
    }

    func setDailyMorningNotificationEnabled(_ enabled: Bool) {
        isDailyMorningNotificationEnabled = enabled
        manageSettingsUseCase.setDailyMorningNotificationEnabled(enabled)
    }

    func setUsageAlertEnabled(_ enabled: Bool) {
        isUsageAlertEnabled = enabled
        manageSettingsUseCase.setUsageAlertEnabled(enabled)
    }

    func loadState() async {
        isScreenTimeAuthorized = manageSettingsUseCase.refreshScreenTimeAuthorization()
        notificationPermissionState = await manageSettingsUseCase.notificationAuthorizationState()
        isNotificationDeferredBySummary = await manageSettingsUseCase.isNotificationDeferredByScheduledSummary()
        isDailyMorningNotificationEnabled = manageSettingsUseCase.isDailyMorningNotificationEnabled
        isUsageAlertEnabled = manageSettingsUseCase.isUsageAlertEnabled
        isStrictLockEnabled = manageGroupsUseCase.isStrictLockEnabled
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
