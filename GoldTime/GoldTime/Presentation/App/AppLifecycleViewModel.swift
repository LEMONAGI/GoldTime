
//
//  AppLifecycleViewModel.swift
//  GoldTime
//

import Foundation

@MainActor
@Observable
final class AppLifecycleViewModel {
    var showLockOptions = false
    var pendingGroupID: UUID?

    private let authorizeUseCase: AuthorizeUseCase
    private let syncProtectionUseCase: SyncProtectionUseCase
    private let shieldRepository: any ShieldRepository
    private let notificationRepository: any NotificationRepository
    private let analyticsRepository: any AnalyticsRepository

    init(
        authorizeUseCase: AuthorizeUseCase? = nil,
        syncProtectionUseCase: SyncProtectionUseCase? = nil,
        shieldRepository: (any ShieldRepository)? = nil,
        notificationRepository: (any NotificationRepository)? = nil,
        analyticsRepository: (any AnalyticsRepository)? = nil
    ) {
        let resolvedShield = shieldRepository ?? ShieldRepositoryImpl()
        let resolvedNotification = notificationRepository ?? NotificationRepositoryImpl()
        self.shieldRepository = resolvedShield
        self.notificationRepository = resolvedNotification
        self.analyticsRepository = analyticsRepository ?? AnalyticsRepositoryImpl()
        self.authorizeUseCase = authorizeUseCase ?? AuthorizeUseCase(
            authRepository: AuthorizationRepositoryImpl(),
            notificationRepository: resolvedNotification
        )
        self.syncProtectionUseCase = syncProtectionUseCase ?? SyncProtectionUseCase(
            groupRepository: GroupRepositoryImpl(),
            screenTimeRepository: ScreenTimeRepositoryImpl()
        )
    }

    func appDidAppear() {
        syncProtectionRulesIfAuthorized()
        refreshLockOptionsPresentation()
    }

    func appDidOpenURL() {
        refreshLockOptionsPresentation()
    }

    func appDidBecomeActive() {
        authorizeUseCase.refresh()
        syncProtectionRulesIfAuthorized()
        refreshLockOptionsPresentation()
        drainPendingAnalyticsEvents()
        updateCohortUserProperties()
        notificationRepository.clearDeliveredNotifications()
        MonitoringBackgroundTask.scheduleNext()
    }

    /// extension이 SharedStore에 쌓아둔 분석 이벤트(shield_hit, screen_time_error 등)를
    /// Firebase로 전송한다. extension은 Firebase를 링크하지 않으므로 메인 앱이 대신 보낸다.
    private func drainPendingAnalyticsEvents() {
        for event in SharedStore.drainPendingAnalyticsEvents() {
            analyticsRepository.log(.custom(name: event.name, parameters: event.parameters))
        }
    }

    /// 적용된 그룹의 규칙 형태를 user property로 심어 코호트 분석 축을 만든다.
    /// 미승인 유저에는 stale property를 남기지 않도록 권한이 있을 때만 갱신한다.
    private func updateCohortUserProperties() {
        guard authorizeUseCase.isAuthorized else { return }
        let groups = GroupRepositoryImpl().screenTimeGroups
        let properties = UserCohortProperties(groups: groups)
        for entry in properties.entries {
            analyticsRepository.setUserProperty(entry.value, for: entry.name)
        }
    }

    func refreshLockOptionsPresentation() {
        syncProtectionUseCase.prepareForAppActivation()
        if shieldRepository.hasPendingShieldOpenRequest() {
            if let token = shieldRepository.lastRequestedUnlockApplicationToken {
                pendingGroupID = shieldRepository.lockedGroups(containing: token).first?.id
            } else if let webToken = shieldRepository.lastRequestedUnlockWebDomainToken {
                pendingGroupID = shieldRepository.lockedGroups(containing: webToken).first?.id
            }
            // 이 메서드는 한 번의 활성화에서 appDidAppear/appDidBecomeActive/appDidOpenURL로
            // 여러 번 호출될 수 있으므로, 시트가 처음 뜨는 false→true 전환에서만 1회 로깅한다.
            if !showLockOptions {
                analyticsRepository.log(.unlockOptionsShown(lockedCount: shieldRepository.lockedGroups().count))
            }
            showLockOptions = true
        }
    }

    private func syncProtectionRulesIfAuthorized() {
        guard authorizeUseCase.isAuthorized else { return }
        let groups = GroupRepositoryImpl().screenTimeGroups
        do {
            try syncProtectionUseCase.syncIfAuthorized(groups: groups, isAuthorized: true)
        } catch {
            print("Failed to sync protection rules: \(error.localizedDescription)")
        }
    }
}
