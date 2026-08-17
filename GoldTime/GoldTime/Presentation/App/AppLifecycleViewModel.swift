
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

    /// 순서 규칙: **user property 갱신이 이벤트 전송보다 먼저**다. Firebase는 property를
    /// "설정한 이후에 전송된 이벤트"에만 붙이므로, 순서가 뒤집히면 이번 활성화의 이벤트들이
    /// 직전 세션의 권한 값을 달고 나가고 **신규 설치의 첫 활성화에는 권한 속성이 아예 없다**
    /// (`group_snapshot`/`rule_*`을 권한별로 쪼개는 분석에서 첫 세션이 통째로 빠진다).
    /// UI 경로(sync·시트 표시)는 await보다 앞에 둬 Shield 복귀 시트가 늦게 뜨지 않게 한다.
    func appDidBecomeActive() async {
        authorizeUseCase.refresh()
        syncProtectionRulesIfAuthorized()
        refreshLockOptionsPresentation()
        await updateAuthorizationUserProperties()
        updateCohortUserProperties()
        drainPendingAnalyticsEvents()
        updateStrictLockCompletions()
        logGroupSnapshots()
        notificationRepository.clearDeliveredNotifications()
        MonitoringBackgroundTask.scheduleNext()
    }

    /// 권한이 있는 사용자는 적용 그룹이 0개여도 기록해 그룹 수 분포의 분모에서 빠지지 않게 한다.
    /// 한 활성화에서 발생하는 그룹 수와 규칙 이벤트를 같은 익명 `snapshot_id`로 묶는다.
    /// 그룹 UUID는 보내지 않으며, 이 ID는 BigQuery가 사용자의 최신 활성화에 속한 여러 그룹을
    /// 빠짐없이 선택하기 위한 일회성 배치 식별자다.
    private func logGroupSnapshots() {
        guard authorizeUseCase.isAuthorized else { return }
        let groups = GroupRepositoryImpl().screenTimeGroups
        let snapshotID = UUID().uuidString
        let appliedGroupCount = groups.filter(\.isApplied).count
        analyticsRepository.log(
            .groupSnapshot(appliedGroupCount: appliedGroupCount, snapshotID: snapshotID)
        )

        for group in groups {
            guard let payload = RuleGroupSnapshotAnalytics(group: group) else { continue }
            analyticsRepository.log(.ruleGroupSnapshot(payload: payload, snapshotID: snapshotID))
        }
    }

    /// extension이 SharedStore에 쌓아둔 분석 이벤트(shield_lock_started, screen_time_error 등)를
    /// Firebase로 전송한다. extension은 Firebase를 링크하지 않으므로 메인 앱이 대신 보낸다.
    private func drainPendingAnalyticsEvents() {
        for event in SharedStore.drainPendingAnalyticsEvents() {
            analyticsRepository.log(.custom(name: event.name, parameters: event.parameters))
        }
    }

    /// 새 코드에서 시작한 약정만 pending 상태로 보관한다. 권한이 유지된 채 만료 시각에 도달한
    /// 약정은 첫 앱 활성화에서 한 번만 완료로 기록한다.
    ///
    /// **미승인일 때 약정을 폐기하지 않는다(2026-08-17 수정)**: `refresh()` 직후의 `isAuthorized`는
    /// 콜드 스타트에서 transient `false`로 읽힐 수 있고(복구 UI를 "재확인까지 실패해야 띄운다"로
    /// 만든 것과 같은 이유 — Presentation/CLAUDE.md), 폐기는 되돌릴 수 없다. 한 번만 잘못 읽혀도
    /// 진행 중인 약정까지 사라져 그 사용자는 영영 `strict_lock_completed`를 보내지 않고,
    /// 완주율의 **분자만 조용히 깎인다**. 여기서는 전송만 건너뛰고, 실제 철회 폐기는 증거가 있는
    /// 경로(`ContentViewModel.handleScreenTimeRecoveryAppear` — 복구 화면 도달)가 담당한다.
    private func updateStrictLockCompletions() {
        guard authorizeUseCase.isAuthorized else { return }
        for totalDays in analyticsRepository.drainCompletedStrictLockDays(at: Date()) {
            analyticsRepository.log(.strictLockCompleted(totalDays: totalDays))
        }
    }

    /// 적용된 그룹의 규칙 형태를 user property로 심어 코호트 분석 축을 만든다.
    /// 미승인 유저에는 stale property를 남기지 않도록 권한이 있을 때만 갱신한다.
    private func updateCohortUserProperties() {
        // [삭제 예정 — TODO.md] 1.3.0에서 group_snapshot과 중복이라 폐기한 사용자 속성의 기존 값을
        // 지운다. 1.2.x에서 올라온 사용자가 앱을 **한 번** 열면 서버 값이 사라지므로, 1.2.x를 쓰는
        // 사용자가 없어지면 이 줄은 아무 일도 안 하면서 매 활성화마다 돌기만 한다. 그때 지운다
        // (특정 버전에 예약하지 말고 버전 분포를 보고 판단).
        // 같은 줄이 `ContentViewModel.updateCohortUserProperties`에도 있다 — 지울 때 함께 지운다.
        analyticsRepository.setUserProperty(nil, for: "active_group_count")
        guard authorizeUseCase.isAuthorized else { return }
        let groups = GroupRepositoryImpl().screenTimeGroups
        let properties = UserCohortProperties(groups: groups)
        for entry in properties.entries {
            analyticsRepository.setUserProperty(entry.value, for: entry.name)
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
