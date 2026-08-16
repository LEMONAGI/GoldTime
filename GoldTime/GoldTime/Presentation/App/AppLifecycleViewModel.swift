
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

    func appDidBecomeActive() async {
        authorizeUseCase.refresh()
        syncProtectionRulesIfAuthorized()
        refreshLockOptionsPresentation()
        drainPendingAnalyticsEvents()
        updateStrictLockCompletions()
        updateCohortUserProperties()
        logGroupSnapshot()
        logRuleGroupSnapshots()
        await updateAuthorizationUserProperties()
        notificationRepository.clearDeliveredNotifications()
        MonitoringBackgroundTask.scheduleNext()
    }

    /// 권한이 있는 사용자는 적용 그룹이 0개여도 기록해 그룹 수 분포의 분모에서 빠지지 않게 한다.
    private func logGroupSnapshot() {
        guard authorizeUseCase.isAuthorized else { return }
        let appliedGroupCount = GroupRepositoryImpl().screenTimeGroups.filter(\.isApplied).count
        analyticsRepository.log(.groupSnapshot(appliedGroupCount: appliedGroupCount))
    }

    /// extension이 SharedStore에 쌓아둔 분석 이벤트(shield_lock_started, screen_time_error 등)를
    /// Firebase로 전송한다. extension은 Firebase를 링크하지 않으므로 메인 앱이 대신 보낸다.
    private func drainPendingAnalyticsEvents() {
        for event in SharedStore.drainPendingAnalyticsEvents() {
            analyticsRepository.log(.custom(name: event.name, parameters: event.parameters))
        }
    }

    /// 새 코드에서 시작한 약정만 pending 상태로 보관한다. 권한이 유지된 채 만료 시각에 도달한
    /// 약정은 첫 앱 활성화에서 한 번만 완료로 기록하고, 권한이 없으면 완주로 오인하지 않도록 버린다.
    private func updateStrictLockCompletions() {
        guard authorizeUseCase.isAuthorized else {
            analyticsRepository.discardAllStrictLockCommitments()
            return
        }
        for days in analyticsRepository.drainCompletedStrictLockDays(at: Date()) {
            analyticsRepository.log(.strictLockCompleted(days: days))
        }
    }

    /// 적용된 그룹의 규칙 형태를 user property로 심어 코호트 분석 축을 만든다.
    /// 미승인 유저에는 stale property를 남기지 않도록 권한이 있을 때만 갱신한다.
    private func updateCohortUserProperties() {
        // 1.3.0에서 group_snapshot과 중복이라 폐기한 사용자 속성의 기존 값을 지운다.
        analyticsRepository.setUserProperty(nil, for: "active_group_count")
        guard authorizeUseCase.isAuthorized else { return }
        let groups = GroupRepositoryImpl().screenTimeGroups
        let properties = UserCohortProperties(groups: groups)
        for entry in properties.entries {
            analyticsRepository.setUserProperty(entry.value, for: entry.name)
        }
    }

    /// 적용 그룹마다 현재 설정을 한 이벤트로 기록한다. 같은 사용자가 앱을 자주 열어도 GA4에서는
    /// 이벤트 수가 아닌 총 사용자 수로 규칙 채택률을 비교하고, BigQuery에서는 최신 스냅샷을 쓴다.
    private func logRuleGroupSnapshots() {
        guard authorizeUseCase.isAuthorized else { return }
        let groups = GroupRepositoryImpl().screenTimeGroups
        for group in groups {
            guard let payload = RuleGroupSnapshotAnalytics(group: group) else { continue }
            analyticsRepository.log(.ruleGroupSnapshot(payload: payload))
        }
    }

    /// 권한을 거부하거나 설정에서 철회한 경우도 `false`로 덮어써 stale `true`를 남기지 않는다.
    private func updateAuthorizationUserProperties() async {
        let notificationState = await notificationRepository.authorizationState()
        let properties = AuthorizationAnalyticsProperties(
            screenTimeAuthorized: authorizeUseCase.isAuthorized,
            notificationState: notificationState
        )
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
