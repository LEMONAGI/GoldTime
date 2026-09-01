//
//  ContentViewModel.swift
//  GoldTime
//

import FamilyControls
import Foundation

enum GoldTimeTab: Hashable {
    case home
    case stats
    case settings
}

struct GoldTimeAlertMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func == (lhs: GoldTimeAlertMessage, rhs: GoldTimeAlertMessage) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

/// 이미 사용한 시간보다 작은 한도로 바꿔 즉시 잠기게 될 때 띄우는 확인 경고.
struct LimitLockWarning: Identifiable {
    /// 즉시 잠금이 일어나는 규칙 종류. 일일 한도는 자정까지 잠금, 쿨다운은 휴식 진입.
    enum Rule: Equatable {
        case dailyLimit(minutes: Int)
        case cooldown(usageMinutes: Int, durationMinutes: Int)
    }
    let id = UUID()
    let groupID: UUID
    let groupName: String
    let usedMinutes: Int
    let rule: Rule
    /// 요일별 모드 커밋의 즉시 잠금 경고면 확정 시 이 규칙 전체를 적용한다.
    /// `rule`은 오늘 투영 규칙으로, 경고 문구(오늘 한도/예산)용으로만 보관한다.
    var weekdayRules: [DayRule]? = nil
}

/// draft 그룹을 "적용하기"로 commit하기 전, 이후 수정에 광고가 필요함을 안내하는 확인.
struct ApplyGroupConfirmation: Identifiable {
    let id = UUID()
    let groupID: UUID
    let groupName: String
}

@MainActor
@Observable
final class ContentViewModel {
    private static let hasCompletedInitialHomeEntryKey = "hasCompletedInitialHomeEntry"
    /// 연장 불가 베타 배너의 금빛 발광을 이미 봤는지(첫 탭 후 true). 메인 앱 전용 일회성 플래그라
    /// `UserDefaults.standard`에 둔다(extension 공유 불필요 — `hasCompletedInitialHomeEntry` 선례).
    private static let hasSeenStrictLockBetaAnnouncementKey = "hasSeenStrictLockBetaAnnouncement"

    var selectedTab = GoldTimeTab.home
    var isAuthorized: Bool
    var isNotificationAuthorized: Bool = false
    var isCheckingPermissions: Bool = true
    var isFullyAuthorized: Bool { isAuthorized && isNotificationAuthorized }
    var hasCompletedInitialHomeEntry: Bool
    /// 연장 불가 베타 배너의 금빛 발광을 이미 봤는지(첫 탭 시 true로 올라가 발광이 꺼진다).
    var hasSeenStrictLockBetaAnnouncement: Bool
    // 온보딩 완료 플래그가 진입의 단일 기준. 스크린타임 허용 직후 isAuthorized가 true로
    // 바뀌어도 온보딩(알림/광고 단계)을 끝까지 마치기 전에는 홈으로 넘어가면 안 된다.
    var shouldShowInitialOnboarding: Bool { !hasCompletedInitialHomeEntry }
    /// 온보딩 시작 단계. 진행하다 앱을 종료한 경우 저장된 단계로 복원하고,
    /// 없으면 스크린타임 권한 보유 여부로 기본 시작 단계를 정한다.
    var onboardingStartStep: OnboardingStep {
        if let raw = userDefaults.string(forKey: OnboardingViewModel.savedStepKey),
           let saved = OnboardingStep(rawValue: raw) {
            return saved
        }
        return isAuthorized ? .notificationPermission : .intro
    }
    var groups: [ScreenTimeGroup] = []
    var pickerSelection = FamilyActivitySelection(includeEntireCategory: true)
    var pickerGroupID: UUID?
    var isPickerPresented = false
    var isMonitoring = false
    var errorMessage: String?
    var successMessage: String?
    var alertMessage: GoldTimeAlertMessage?
    var pendingLimitLockWarning: LimitLockWarning?
    var pendingApplyConfirmation: ApplyGroupConfirmation?
    private var stagedLimitLockWarning: LimitLockWarning?
    /// 규칙 편집 적용 후 시트가 닫히면 띄울 단순 안내(예: 휴식 중 휴식 시간 변경).
    private var stagedRuleEditInfo: GoldTimeAlertMessage?
    private var pendingDeletedGroupName: String?
    /// 연장 불가 시트 표시 대상 그룹(nil이면 시트 닫힘). ruleEditorGroupID와 동일 패턴.
    var strictLockSheetGroupID: UUID?
    /// 스크린타임 권한 복구 화면에서 연장 불가 기간 철회를 감지해 이미 1회 로깅했는지(중복 로깅 방지).
    private var didLogStrictRevoke = false

    var isReconnecting = false
    var isScreenTimeRecoveryPresented = false
    var isRequestingScreenTimeAuthorization = false
    var screenTimeRecoveryErrorMessage: String?

    var ruleEditorGroupID: UUID?
    var ruleEditorSelectedKind: GroupRuleKind = .dailyLimit
    /// 편집 대상 그룹에 이미 커밋된 규칙(없으면 nil). 시트의 체크표시 표시에만 쓴다.
    var ruleEditorCurrentKind: GroupRuleKind?
    var ruleEditorTimeWindows: [TimeWindow] = []
    var limitPickerHours = 0
    var limitPickerMinutes = 30
    var ruleEditorCooldownUsageMinutes = SharedStore.ScreenTimeGroup.defaultCooldownUsageMinutes
    var ruleEditorCooldownDurationMinutes = SharedStore.ScreenTimeGroup.defaultCooldownDurationMinutes
    /// 규칙 편집기의 요일별 규칙 편집 상태. nil이면 요일별 모드 OFF(기존 규칙 3종).
    var ruleEditorWeekdayRules: [DayRule]?

    var isShieldActive: Bool
    var oneMinuteRemaining: Int
    var oneMinuteDailyLimit: Int
    var shieldOverrideUntil: Date?
    var todayStats: DailyStats
    var statsReport: StatsReport
    var adFreeStreakDays: Int
    var maxAdFreeStreakDays: Int
    var lockedGroupIDs: Set<UUID> = []
    var overrideGroupIDs: Set<UUID> = []
    var validGroupIDs: Set<UUID> = []
    var untrackedGroupIDs: Set<UUID> = []
    var overrideUntilByGroupID: [UUID: Date] = [:]
    var usedTimeByGroupID: [UUID: Int] = [:]
    var overrideBaselineUsedTimeByGroupID: [UUID: Int] = [:]
    var overrideGrantedMinutesByGroupID: [UUID: Int] = [:]
    var cooldownEndByGroupID: [UUID: Date] = [:]
    var unlockSheetGroupID: UUID? = nil
    var isUnlockSheetPresented = false

    var isAdGatePresented = false
    var adGateFallbackLabel: String = ""
    private var adGatePendingAction: (() -> Void)? = nil

    var isRuleCommitAdGatePresented = false
    private var ruleCommitAdRewardEarned = false

    private let manageGroupsUseCase: ManageGroupsUseCase
    private let syncProtectionUseCase: SyncProtectionUseCase
    private let loadDashboardUseCase: LoadDashboardUseCase
    private let authorizeUseCase: AuthorizeUseCase
    private let analyticsRepository: any AnalyticsRepository
    private let userDefaults: UserDefaults
    private var authorizationObservation: AuthorizationObservation?

    init(
        manageGroupsUseCase: ManageGroupsUseCase? = nil,
        syncProtectionUseCase: SyncProtectionUseCase? = nil,
        loadDashboardUseCase: LoadDashboardUseCase? = nil,
        authorizeUseCase: AuthorizeUseCase? = nil,
        analyticsRepository: (any AnalyticsRepository)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        let groupRepo = GroupRepositoryImpl()
        let shieldRepo = ShieldRepositoryImpl()
        let statsRepo = StatsRepositoryImpl()
        let screenTimeRepo = ScreenTimeRepositoryImpl()
        let authRepo = AuthorizationRepositoryImpl()
        let notifRepo = NotificationRepositoryImpl()

        self.manageGroupsUseCase = manageGroupsUseCase ?? ManageGroupsUseCase(
            groupRepository: groupRepo,
            screenTimeRepository: screenTimeRepo
        )
        self.syncProtectionUseCase = syncProtectionUseCase ?? SyncProtectionUseCase(
            groupRepository: groupRepo,
            screenTimeRepository: screenTimeRepo
        )
        self.loadDashboardUseCase = loadDashboardUseCase ?? LoadDashboardUseCase(
            shieldRepository: shieldRepo,
            statsRepository: statsRepo,
            screenTimeRepository: screenTimeRepo
        )
        self.authorizeUseCase = authorizeUseCase ?? AuthorizeUseCase(
            authRepository: authRepo,
            notificationRepository: notifRepo
        )
        self.analyticsRepository = analyticsRepository ?? AnalyticsRepositoryImpl()
        self.userDefaults = userDefaults

        isAuthorized = self.authorizeUseCase.isAuthorized
        hasCompletedInitialHomeEntry = userDefaults.bool(forKey: Self.hasCompletedInitialHomeEntryKey)
        hasSeenStrictLockBetaAnnouncement = userDefaults.bool(forKey: Self.hasSeenStrictLockBetaAnnouncementKey)
        isStrictLockFeatureEnabled = self.manageGroupsUseCase.isStrictLockEnabled
        usedTimeByGroupID = shieldRepo.usedTimeByGroupID
        isShieldActive = shieldRepo.isShieldActive
        oneMinuteRemaining = shieldRepo.oneMinuteRemaining
        oneMinuteDailyLimit = ScreenTimeGroupPolicy.oneMinuteDailyLimit
        shieldOverrideUntil = shieldRepo.currentShieldOverrideUntil
        let initialTodayStats = statsRepo.todayStats
        todayStats = initialTodayStats
        statsReport = StatsReport(
            todayStats: initialTodayStats,
            weeklyStats: statsRepo.statsForCalendarWeek(weekOffset: 0),
            previousWeekStats: statsRepo.statsForCalendarWeek(weekOffset: -1),
            monthlyStats: statsRepo.lastNDayStats(30),
            trackingStartDate: statsRepo.trackingStartDate
        )
        adFreeStreakDays = 0
        maxAdFreeStreakDays = 0

        authorizationObservation = self.authorizeUseCase.observeAuthorizationChanges { [weak self] isAuthorized in
            self?.applyScreenTimeAuthorization(isAuthorized)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizeUseCase.refresh()
            let authorized = self.authorizeUseCase.isAuthorized
            let state = await self.authorizeUseCase.notificationState()
            self.applyScreenTimeAuthorization(authorized)
            self.isNotificationAuthorized = [NotificationPermissionState.authorized, .provisional, .ephemeral].contains(state)
            self.markInitialHomeEntryIfReady()
            self.isCheckingPermissions = false
        }
    }

    var isRuleEditorPresented: Bool {
        ruleEditorGroupID != nil
    }

    /// 자정 근처(23:30+)라 편집해도 곧 사용량 추적이 멈출 때 편집 상세에 띄울 안내.
    /// 일일 한도·쿨다운 상세에서만 노출한다(시간대별 차단은 영향 없음 — View에서 분기).
    var nearMidnightEditNotice: String? {
        guard manageGroupsUseCase.isNearMidnightEditNoticeWindow() else { return nil }
        return String(localized: "content.nearMidnightEditNotice")
    }

    func setRuleEditorPresented(_ isPresented: Bool) {
        if !isPresented {
            ruleEditorGroupID = nil
        }
    }

    func refreshAuthorization() {
        authorizeUseCase.refresh()
        applyScreenTimeAuthorization(authorizeUseCase.isAuthorized)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let state = await self.authorizeUseCase.notificationState()
            self.isNotificationAuthorized = [NotificationPermissionState.authorized, .provisional, .ephemeral].contains(state)
            self.markInitialHomeEntryIfReady()
        }
    }

    func loadState() {
        refreshAuthorization()
        markInitialHomeEntryIfReady()
        ReviewRequestService.requestIfEligible()
        syncProtectionUseCase.prepareForAppActivation()
        groups = manageGroupsUseCase.currentGroups()
        if isAuthorized {
            syncProtectionRules()
        } else {
            refreshDashboardState()
        }
        Task { await requestScreenTimeAuthorizationOnEntry() }
    }

    func requestScreenTimeAuthorizationOnEntry() async {
        guard hasCompletedInitialHomeEntry, !isRequestingScreenTimeAuthorization else { return }

        isRequestingScreenTimeAuthorization = true
        defer { isRequestingScreenTimeAuthorization = false }

        authorizeUseCase.refresh()
        if authorizeUseCase.isAuthorized {
            completeScreenTimeAuthorizationRestore()
            return
        }

        do {
            try await authorizeUseCase.requestScreenTime()
        } catch {
            authorizeUseCase.refresh()
            if authorizeUseCase.isAuthorized {
                completeScreenTimeAuthorizationRestore()
            } else {
                presentScreenTimeRecovery()
            }
            return
        }

        if authorizeUseCase.isAuthorized {
            completeScreenTimeAuthorizationRestore()
        } else {
            presentScreenTimeRecovery()
        }
    }

    func refreshDashboardState() {
        let state = loadDashboardUseCase.refresh(groups: groups)
        applyDashboardState(state)
        // 설정에서 연장 불가 기능 토글을 바꿨을 수 있으므로 홈 갱신 시 함께 읽는다.
        isStrictLockFeatureEnabled = manageGroupsUseCase.isStrictLockEnabled
    }

    func handlePickerPresentationChange(isPresented: Bool) {
        if !isPresented {
            pickerGroupID = nil
        }
    }

    func addGroup() {
        do {
            let newGroup = try manageGroupsUseCase.makeNewGroup(currentCount: groups.count)
            groups.append(newGroup)
            persistGroups(shouldSyncProtection: false)
            successMessage = nil
            errorMessage = nil
        } catch {
            alertMessage = GoldTimeAlertMessage(title: String(localized: "content.alert.groupLimit.title"), message: error.localizedDescription)
        }
    }

    func deleteGroup(_ id: UUID) {
        guard let deletingGroup = groups.first(where: { $0.id == id }) else { return }
        var updated = groups
        guard manageGroupsUseCase.deleteGroup(id: id, in: &updated) else {
            // 연장 불가 기간 중이면 Domain이 삭제를 거부한다. 진입 경로(requestDeleteGroup)에서 이미
            // 걸러지지만, 광고 게이트 완료 후 직접 호출되는 경로에도 방어를 겹친다.
            if let group = groups.first(where: { $0.id == id }), group.isStrictLockActive() {
                alertMessage = strictBlockedAlert(for: group, kind: .delete)
            }
            return
        }
        groups = updated
        successMessage = nil
        errorMessage = nil
        persistGroups()
        analyticsRepository.log(.groupDeleted(wasApplied: deletingGroup.isApplied))
    }

    func updateGroupName(_ id: UUID, name: String) {
        updateGroup(id, shouldSyncProtection: false) { groups in
            manageGroupsUseCase.updateName(id: id, name: name, in: &groups)
        }
    }

    func presentPicker(for group: ScreenTimeGroup) {
        pickerGroupID = group.id
        pickerSelection = group.selection.supportedTokenSelection
        isPickerPresented = true
    }

    func presentRuleEditor(for group: ScreenTimeGroup) {
        // 연장 불가 기간 중엔 편집기 진입 자체를 막고 만료일을 안내한다(우회 방지).
        if group.isStrictLockActive() {
            alertMessage = strictBlockedAlert(for: group, kind: .edit)
            return
        }
        let clamped = min(group.dailyLimitMinutes, 5 * 60 + 55)
        limitPickerHours = clamped / 60
        let rawMinutes = clamped % 60
        limitPickerMinutes = (rawMinutes / 5) * 5
        ruleEditorSelectedKind = group.ruleKind ?? .dailyLimit
        ruleEditorCurrentKind = group.ruleKind
        ruleEditorTimeWindows = group.timeWindows
        ruleEditorCooldownUsageMinutes = group.cooldownUsageMinutes
        ruleEditorCooldownDurationMinutes = group.cooldownDurationMinutes
        ruleEditorWeekdayRules = group.weekdayRules
        ruleEditorGroupID = group.id
    }

    func commitPickerSelection() {
        guard let groupID = pickerGroupID else { return }
        let selection = pickerSelection
        updateGroup(groupID) { groups in
            manageGroupsUseCase.updateSelection(id: groupID, selection: selection, in: &groups)
        }
    }

    /// 규칙 편집기의 확인. 적용된 그룹에 집행 영향 변경이 있으면 광고 게이트 cover를 띄운다
    /// (보기만 하는 진입은 무료 — 게이트는 진입이 아니라 변경 커밋에 건다). "광고를 봐야 한다"는
    /// 안내는 cover 안 1단계(`RuleCommitAdGateView`)가 담당한다 — 냅다 광고가 아니라
    /// 안내 → 확인 → 광고. 시트 안 다이얼로그 → cover 연쇄는 타이밍 글리치로 폐기(Presentation/CLAUDE.md).
    func commitRuleSelection() {
        if requiresAdForRuleCommit() {
            isRuleCommitAdGatePresented = true
            return
        }
        performRuleCommit()
    }

    /// 규칙 편집기의 실제 커밋. 요일별 모드면 요일 규칙을, 아니면 선택된 규칙 종류를 각각 적용한다.
    func performRuleCommit() {
        if ruleEditorWeekdayRules != nil {
            commitWeekdayRules()
            return
        }
        switch ruleEditorSelectedKind {
        case .dailyLimit:
            commitDailyLimitRule()
        case .timeWindows:
            commitTimeWindowsRule()
        case .cooldown:
            commitCooldownRule()
        }
    }

    /// View가 완료 시점에 게이트 여부를 미리 알아야 할 때 사용 — 광고 cover는 시스템 슬라이드
    /// 대신 자체 등장 연출(scrim 페이드+카드 rise)을 쓰므로, ContentView가 게이트 경로에서만
    /// 프레젠테이션 애니메이션을 끄기 위해 커밋 전에 조회한다.
    var isRuleCommitAdGateRequired: Bool { requiresAdForRuleCommit() }

    /// 적용된 그룹에 집행 영향 변경이 있어 커밋 시 광고 게이트가 필요한지 판단한다.
    /// draft는 무료, 무효한 요일 상태는 광고 없이 커밋으로 보내 기존 검증 alert 경로를 태운다.
    private func requiresAdForRuleCommit() -> Bool {
        guard let id = ruleEditorGroupID,
              let group = groups.first(where: { $0.id == id }),
              group.isApplied else { return false }
        if let rules = ruleEditorWeekdayRules,
           WeekdayRulePolicy.firstInvalidReason(for: rules) != nil {
            return false
        }
        return hasEnforcementRelevantChange(group: group)
    }

    /// 편집기 상태가 그룹의 현재 규칙과 집행상 다른지 판단한다(요일 ↔ 단일 전환, 요일 규칙 배열
    /// 변경, 단일 규칙 종류/파라미터 변경). `isExplicitlyUnrestricted`는 표시 전용이라 제외한다.
    private func hasEnforcementRelevantChange(group: ScreenTimeGroup) -> Bool {
        if let editorRules = ruleEditorWeekdayRules {
            guard let groupRules = group.weekdayRules else { return true }   // 단일 → 요일 전환
            return normalizedForEnforcement(editorRules) != normalizedForEnforcement(groupRules)
        }
        if group.weekdayRules != nil { return true }   // 요일 → 단일 전환

        if ruleEditorSelectedKind != group.ruleKind { return true }
        switch ruleEditorSelectedKind {
        case .dailyLimit:
            return limitPickerHours * 60 + limitPickerMinutes != group.dailyLimitMinutes
        case .timeWindows:
            return ruleEditorTimeWindows != group.timeWindows
        case .cooldown:
            return ruleEditorCooldownUsageMinutes != group.cooldownUsageMinutes
                || ruleEditorCooldownDurationMinutes != group.cooldownDurationMinutes
        }
    }

    /// 표시 전용 `isExplicitlyUnrestricted`를 false로 통일한 사본. 이 플래그만 바뀐
    /// "암묵 → 명시 승격" 커밋은 집행에 무영향이라 광고 없이 통과시킨다.
    private func normalizedForEnforcement(_ rules: [DayRule]) -> [DayRule] {
        rules.map {
            var copy = $0
            copy.isExplicitlyUnrestricted = false
            return copy
        }
    }

    func ruleCommitAdGateCompleted() {
        ruleCommitAdRewardEarned = true
        isRuleCommitAdGatePresented = false
    }

    func ruleCommitAdGateCancelled() {
        isRuleCommitAdGatePresented = false
    }

    /// 광고 cover가 닫힌 뒤 호출. 보상을 얻었으면 그때 커밋한다(cover dismiss와 시트 dismiss·
    /// staged alert가 같은 사이클에 겹치지 않도록 순서 분리).
    func handleRuleCommitAdGateDismiss() {
        guard ruleCommitAdRewardEarned else { return }
        ruleCommitAdRewardEarned = false
        performRuleCommit()
    }

    /// 요일별 규칙 커밋. 검증 → 오늘 투영 기준 즉시 잠금 경고 판단 → persist+sync.
    private func commitWeekdayRules() {
        guard let id = ruleEditorGroupID, let rules = ruleEditorWeekdayRules else { return }

        // 뷰에서 완료를 막아도 VM에서 한 번 더 검증한다.
        if let reason = WeekdayRulePolicy.firstInvalidReason(for: rules) {
            alertMessage = GoldTimeAlertMessage(
                title: String(localized: "content.alert.weekdayCheck.title"),
                message: reason.userMessage
            )
            return
        }

        let used = usedTimeByGroupID[id] ?? 0
        let todayRule = rules[WeekdayRulePolicy.weekdayIndex(for: Date())]
        // 즉시 잠금 경고는 오늘 투영 규칙 기준(일일/쿨다운이고 새 예산 <= 사용량). 시트가 닫힌 뒤 띄운다.
        // 이미 잠김/휴식/override 중이면 새 전환이 아니므로 경고를 생략하고 바로 적용한다.
        if isGroupCurrentlyOpen(id), used > 0,
           let warning = weekdayImmediateLockWarning(id: id, todayRule: todayRule, used: used, rules: rules) {
            stagedLimitLockWarning = warning
            ruleEditorGroupID = nil
            return
        }

        // 오늘 투영 변경 여부는 적용 전에 판정한다(applyWeekdayRules가 groups를 갱신하므로).
        let todayChanged = groups.first(where: { $0.id == id }).map { group in
            changesTodayProjection(of: group) { $0.weekdayRules = rules }
        } ?? true

        applyWeekdayRules(id: id, rules: rules)

        // 자정 근처 안내: 오늘 투영 kind가 daily/cooldown이고 오늘 투영이 실제로 바뀔 때만
        // (다른 요일만 편집한 커밋은 churn 가드가 재등록을 건너뛰어 안내가 거짓 정보가 된다).
        let todayTracked = todayRule.kind == .dailyLimit || todayRule.kind == .cooldown
        if isAppliedGroup(id) && todayTracked && todayChanged
            && manageGroupsUseCase.isNearMidnightMonitorTooShort() {
            stagedRuleEditInfo = nearMidnightApplyNotice
        }
        ruleEditorGroupID = nil
    }

    /// 오늘 투영 규칙이 이미 쓴 시간보다 작은 예산이면 즉시 잠기므로 확인 경고를 만든다.
    /// 확정 시 base 규칙이 아니라 요일 규칙 전체를 적용하도록 `weekdayRules`를 함께 싣는다.
    private func weekdayImmediateLockWarning(id: UUID, todayRule: DayRule, used: Int, rules: [DayRule]) -> LimitLockWarning? {
        let name = groups.first(where: { $0.id == id })?.name ?? String(localized: "content.thisGroup")
        switch todayRule.kind {
        case .dailyLimit where todayRule.dailyLimitMinutes <= used:
            return LimitLockWarning(
                groupID: id,
                groupName: name,
                usedMinutes: used,
                rule: .dailyLimit(minutes: todayRule.dailyLimitMinutes),
                weekdayRules: rules
            )
        case .cooldown where todayRule.cooldownUsageMinutes <= used:
            return LimitLockWarning(
                groupID: id,
                groupName: name,
                usedMinutes: used,
                rule: .cooldown(usageMinutes: todayRule.cooldownUsageMinutes, durationMinutes: todayRule.cooldownDurationMinutes),
                weekdayRules: rules
            )
        default:
            return nil
        }
    }

    private func applyWeekdayRules(id: UUID, rules: [DayRule]) {
        updateGroup(id) { groups in
            manageGroupsUseCase.updateWeekdayRules(id: id, rules: rules, in: &groups)
        }
    }

    /// 그룹이 현재 자유롭게 사용 가능한(잠김X·휴식X·override X) 상태인지.
    /// 편집으로 "즉시 잠금/휴식 진입" 확인 알럿을 띄울지 판단하는 데 쓴다(전환이 실제로 일어날 때만).
    private func isGroupCurrentlyOpen(_ id: UUID) -> Bool {
        !lockedGroupIDs.contains(id) && !overrideGroupIDs.contains(id)
    }

    /// 자정 직전(23:45+) 적용·수정 직후 안내 alert. 모니터 등록이 막혀 규칙이 00:00부터
    /// 적용되는 상황을 알린다. 일일 한도·쿨다운만 — 시간대 차단은 측정창과 무관해 제외한다.
    /// 커밋 경로에서는 `changesTodayProjection`이 true일 때만 띄운다(아래 참조).
    private var nearMidnightApplyNotice: GoldTimeAlertMessage {
        GoldTimeAlertMessage(
            title: String(localized: "content.alert.applyNotice.title"),
            message: String(localized: "content.alert.applyNotice.message")
        )
    }

    /// 모니터(자정 측정창)에 등록돼 23:45 too short의 영향을 받는 규칙인지(일일 한도·쿨다운).
    private func isMonitorTrackedRule(_ kind: SharedStore.ScreenTimeGroup.RuleKind?) -> Bool {
        kind == .dailyLimit || kind == .cooldown
    }

    /// 이 커밋이 **오늘의 집행 투영본**(`resolved(on:)`)을 실제로 바꾸는지. 자정 안내는 "지금은
    /// 모니터 재등록이 막힌다"는 안내인데, 오늘 투영이 그대로면(예: 다른 요일만 편집한 커밋)
    /// `syncDailyMonitoring`의 churn 가드(`last != group`)가 재등록 자체를 건너뛰어 모니터가
    /// 빠질 일도 미추적 갭도 없다 — 그때 안내가 뜨면 거짓 정보(false positive)라서 거른다.
    /// 비교는 churn 가드와 같은 술어(투영본 값 동등성)를 쓴다.
    private func changesTodayProjection(of group: ScreenTimeGroup, edit: (inout ScreenTimeGroup) -> Void) -> Bool {
        var edited = group
        edit(&edited)
        let now = Date()
        return group.resolved(on: now) != edited.resolved(on: now)
    }

    private func commitCooldownRule() {
        guard let id = ruleEditorGroupID else { return }
        let usage = ruleEditorCooldownUsageMinutes
        let duration = ruleEditorCooldownDurationMinutes

        // 뷰에서 저장 버튼을 막아도, VM에서 한 번 더 검증한다.
        if let reason = CooldownPolicy.firstInvalidReason(usageMinutes: usage, cooldownMinutes: duration) {
            alertMessage = GoldTimeAlertMessage(title: String(localized: "content.alert.cooldownCheck.title"), message: reason.userMessage)
            return
        }

        let used = usedTimeByGroupID[id] ?? 0
        // 이미 사용한 시간보다 작은 예산이면 즉시 휴식에 들어간다(일일 한도 즉시 잠금과 동일 패턴).
        // 바로 적용하지 말고, 시트가 닫힌 뒤 확인 경고를 띄운다.
        // 단, 이미 잠김/휴식/override 중이면 새 전환이 아니므로 경고를 생략하고 바로 적용한다.
        if isGroupCurrentlyOpen(id) && used > 0 && usage <= used {
            let name = groups.first(where: { $0.id == id })?.name ?? String(localized: "content.thisGroup")
            stagedLimitLockWarning = LimitLockWarning(
                groupID: id,
                groupName: name,
                usedMinutes: used,
                rule: .cooldown(usageMinutes: usage, durationMinutes: duration)
            )
            ruleEditorGroupID = nil
            return
        }

        // 휴식 중에는 예산/휴식 간격을 바꿔도 진행 중인 휴식은 그대로고, 새 값은 다음 주기부터 적용된다.
        // (적용 전 상태로 판단 — applyCooldownRule이 dashboard를 갱신하기 전에 캡처)
        let oldGroup = groups.first(where: { $0.id == id })
        let isResting = (cooldownEndByGroupID[id].map { $0 > Date() }) ?? false
        let settingsChangedWhileResting = isResting && oldGroup != nil
            && (oldGroup!.cooldownUsageMinutes != usage || oldGroup!.cooldownDurationMinutes != duration)
        // 자정 안내는 오늘 투영이 실제로 바뀌는 커밋만(무변경 완료는 churn 가드가 재등록을 건너뜀).
        let todayChanged = oldGroup.map { group in
            changesTodayProjection(of: group) {
                $0.ruleKind = .cooldown
                $0.cooldownUsageMinutes = usage
                $0.cooldownDurationMinutes = duration
                $0.weekdayRules = nil
            }
        } ?? true

        applyCooldownRule(id: id, usage: usage, duration: duration)
        if settingsChangedWhileResting {
            stagedRuleEditInfo = GoldTimeAlertMessage(
                title: String(localized: "content.alert.changeNotice.title"),
                message: String(localized: "content.alert.changeNotice.message")
            )
        } else if isAppliedGroup(id) && todayChanged
            && manageGroupsUseCase.isNearMidnightMonitorTooShort() {
            stagedRuleEditInfo = nearMidnightApplyNotice
        }
        ruleEditorGroupID = nil
    }

    private func applyCooldownRule(id: UUID, usage: Int, duration: Int) {
        updateGroup(id) { groups in
            manageGroupsUseCase.updateRule(
                id: id,
                kind: .cooldown,
                cooldownUsageMinutes: usage,
                cooldownDurationMinutes: duration,
                in: &groups
            )
            // base 규칙 커밋은 요일별 모드 해제를 의미한다(요일별 OFF 커밋 경로). 이미 nil이면 무해한 no-op.
            manageGroupsUseCase.updateWeekdayRules(id: id, rules: nil, in: &groups)
        }
    }

    private func commitDailyLimitRule() {
        guard let id = ruleEditorGroupID else { return }
        let minutes = limitPickerHours * 60 + limitPickerMinutes
        let used = usedTimeByGroupID[id] ?? 0
        // 이미 사용한 시간보다 작은 한도면 즉시 잠긴다(syncDailyMonitoring의 used >= limit 분기).
        // 바로 적용하지 말고, 시트가 닫힌 뒤 확인 경고를 띄운다.
        // 단, 이미 잠김/override 중이면 새 전환이 아니므로 경고를 생략하고 바로 적용한다.
        if isGroupCurrentlyOpen(id) && used > 0 && minutes <= used {
            let name = groups.first(where: { $0.id == id })?.name ?? String(localized: "content.thisGroup")
            stagedLimitLockWarning = LimitLockWarning(
                groupID: id,
                groupName: name,
                usedMinutes: used,
                rule: .dailyLimit(minutes: minutes)
            )
            ruleEditorGroupID = nil
            return
        }

        // 자정 안내는 오늘 투영이 실제로 바뀌는 커밋만(무변경 완료는 churn 가드가 재등록을 건너뜀).
        let todayChanged = groups.first(where: { $0.id == id }).map { group in
            changesTodayProjection(of: group) {
                $0.ruleKind = .dailyLimit
                $0.dailyLimitMinutes = minutes
                $0.weekdayRules = nil
            }
        } ?? true

        applyDailyLimitRule(id: id, minutes: minutes)
        if isAppliedGroup(id) && todayChanged
            && manageGroupsUseCase.isNearMidnightMonitorTooShort() {
            stagedRuleEditInfo = nearMidnightApplyNotice
        }
        ruleEditorGroupID = nil
    }

    private func commitTimeWindowsRule() {
        guard let id = ruleEditorGroupID else { return }
        let windows = ruleEditorTimeWindows

        // 뷰에서 저장 버튼을 막아도, VM에서 한 번 더 검증한다.
        if let reason = TimeWindowPolicy.firstInvalidReason(for: windows) {
            alertMessage = GoldTimeAlertMessage(title: String(localized: "content.alert.timeWindowCheck.title"), message: reason.userMessage)
            return
        }

        // 규칙을 timeWindows로 바꿔도 dailyLimitMinutes는 그대로 보존(되돌릴 때 재사용).
        updateGroup(id) { groups in
            manageGroupsUseCase.updateRule(
                id: id,
                kind: .timeWindows,
                timeWindows: windows,
                in: &groups
            )
            // base 규칙 커밋은 요일별 모드 해제를 의미한다(요일별 OFF 커밋 경로).
            manageGroupsUseCase.updateWeekdayRules(id: id, rules: nil, in: &groups)
        }
        ruleEditorGroupID = nil
    }

    private func applyDailyLimitRule(id: UUID, minutes: Int) {
        updateGroup(id) { groups in
            manageGroupsUseCase.updateRule(
                id: id,
                kind: .dailyLimit,
                dailyLimitMinutes: minutes,
                in: &groups
            )
            // base 규칙 커밋은 요일별 모드 해제를 의미한다(요일별 OFF 커밋 경로).
            manageGroupsUseCase.updateWeekdayRules(id: id, rules: nil, in: &groups)
        }
    }

    /// 규칙 편집기 시트가 닫힌 뒤 호출. 즉시 잠금 경고가 대기 중이면 alert로 띄운다
    /// (시트 dismiss와 alert를 동시에 표시하면 alert가 누락될 수 있어 순서를 분리).
    func handleRuleEditorDismiss() {
        if let staged = stagedLimitLockWarning {
            stagedLimitLockWarning = nil
            pendingLimitLockWarning = staged
            return
        }
        if let info = stagedRuleEditInfo {
            stagedRuleEditInfo = nil
            alertMessage = info
        }
    }

    // warning을 인자로 받는다: .alert(item:)이 버튼 액션 전에 바인딩을 nil로 만들어
    // 상태에서 다시 읽으면 nil이 되기 때문(early-return 버그 방지).
    func confirmLimitLockChange(_ warning: LimitLockWarning) {
        pendingLimitLockWarning = nil
        // 요일별 모드 경고는 base 규칙이 아니라 요일 규칙 전체를 적용한다.
        if let rules = warning.weekdayRules {
            applyWeekdayRules(id: warning.groupID, rules: rules)
            return
        }
        switch warning.rule {
        case .dailyLimit(let minutes):
            applyDailyLimitRule(id: warning.groupID, minutes: minutes)
        case .cooldown(let usage, let duration):
            applyCooldownRule(id: warning.groupID, usage: usage, duration: duration)
        }
    }

    func cancelLimitLockChange() {
        pendingLimitLockWarning = nil
    }

    /// 적용(commit)된 그룹은 우회 방지를 위해 앱 선택 편집·삭제 전에 광고 게이트를 거친다
    /// (규칙 변경은 진입이 아니라 완료 시점 게이트로 옮겨졌다 — `requiresAdForRuleCommit`).
    /// applied는 잠금/연장 상태를 모두 포함(applied ⊃ locked ∪ override)하므로 더 엄격한 기준이다.
    /// draft(미적용) 그룹은 자유롭게 수정·삭제할 수 있도록 게이트 없음.
    private func isEditRestricted(_ id: UUID) -> Bool {
        groups.first(where: { $0.id == id })?.isApplied ?? false
    }

    func requestPickerPresentation(for group: ScreenTimeGroup) {
        // 연장 불가 기간 중엔 앱 선택 편집을 막고 만료일을 안내한다(광고 게이트 진입 전에 차단).
        if group.isStrictLockActive() {
            alertMessage = strictBlockedAlert(for: group, kind: .edit)
            return
        }
        guard isEditRestricted(group.id) else {
            presentPicker(for: group)
            return
        }
        adGatePendingAction = { [weak self] in self?.presentPicker(for: group) }
        adGateFallbackLabel = String(localized: "content.adGate.edit")
        isAdGatePresented = true
    }

    func requestDeleteGroup(_ id: UUID) {
        // 연장 불가 기간 중엔 삭제를 막고 만료일을 안내한다(광고 게이트 진입 전에 차단).
        if let group = groups.first(where: { $0.id == id }), group.isStrictLockActive() {
            alertMessage = strictBlockedAlert(for: group, kind: .delete)
            return
        }
        let name = groups.first(where: { $0.id == id })?.name ?? String(localized: "content.thisGroup")
        guard isEditRestricted(id) else {
            deleteGroup(id)
            presentDeletionCompletedAlert(groupName: name)
            return
        }
        adGatePendingAction = { [weak self] in
            self?.deleteGroup(id)
            self?.pendingDeletedGroupName = name
        }
        adGateFallbackLabel = String(localized: "content.adGate.delete")
        isAdGatePresented = true
    }

    /// 광고 게이트 시트가 닫힌 뒤 호출. 삭제 대기 중인 그룹 이름이 있으면 완료 alert를 띄운다
    /// (시트 dismiss와 alert를 동시에 표시하면 alert가 누락될 수 있어 순서를 분리).
    func handleAdGateDismiss() {
        guard let name = pendingDeletedGroupName else { return }
        pendingDeletedGroupName = nil
        presentDeletionCompletedAlert(groupName: name)
    }

    private func presentDeletionCompletedAlert(groupName: String) {
        let message = GoldTimeAlertMessage(title: String(localized: "content.alert.deleted.title"), message: String(localized: "content.alert.deleted.message \(groupName)"))
        // confirmationDialog/광고 시트가 닫히는 것과 같은 업데이트 사이클에서 alert를 띄우면
        // SwiftUI가 표시를 건너뛴다. 다음 런루프로 미뤄 안정적으로 표시한다.
        Task { @MainActor in
            self.alertMessage = message
        }
    }

    /// draft 그룹 "적용하기". 적용 가능 여부를 검증한 뒤 확인 alert 단계로 넘긴다.
    /// 검증 실패 시 부족한 항목을 안내한다.
    func requestApplyGroup(id: UUID) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        if let reason = applyInvalidReason(of: group) {
            // draft 자체(미적용)는 검증에서 제외하고, 규칙/항목 등 실제 부족분만 안내한다.
            alertMessage = GoldTimeAlertMessage(title: String(localized: "content.alert.cannotApply.title"), message: reason.userMessage)
            return
        }
        pendingApplyConfirmation = ApplyGroupConfirmation(groupID: id, groupName: group.name)
    }

    /// 적용 가능 검증은 isApplied 분기를 빼고 본다(아직 draft이므로 isApplied=false가 당연).
    private func applyInvalidReason(of group: ScreenTimeGroup) -> ScreenTimeGroupPolicy.InvalidReason? {
        var snapshot = group.policySnapshot
        snapshot.isApplied = true
        return ScreenTimeGroupPolicy.invalidReason(for: snapshot)
    }

    // confirmation을 인자로 받는다: .alert(item:)이 버튼 액션 전에 바인딩을 nil로 만들기 때문.
    func confirmApplyGroup(_ confirmation: ApplyGroupConfirmation) {
        pendingApplyConfirmation = nil
        updateGroup(confirmation.groupID) { groups in
            manageGroupsUseCase.markApplied(id: confirmation.groupID, in: &groups)
        }
        if let group = groups.first(where: { $0.id == confirmation.groupID }),
           let payload = RuleGroupSnapshotAnalytics(group: group) {
            analyticsRepository.log(.groupApplied(payload: payload))
            // 자정 직전 적용이면 모니터 등록이 막혀 00:00부터 적용된다. 확인 다이얼로그가
            // 닫히는 사이클과 겹치면 alert가 누락되므로 다음 런루프로 미뤄 띄운다.
            // 요일별 그룹은 오늘 투영 규칙 기준으로 측정창 영향(daily/cooldown)을 판단한다.
            if isMonitorTrackedRule(group.resolved(on: Date()).ruleKind)
                && manageGroupsUseCase.isNearMidnightMonitorTooShort() {
                let notice = nearMidnightApplyNotice
                Task { @MainActor in self.alertMessage = notice }
            }
        }
    }

    func cancelApplyGroup() {
        pendingApplyConfirmation = nil
    }

    func adGateCompleted() {
        adGatePendingAction?()
        adGatePendingAction = nil
        isAdGatePresented = false
    }

    func adGateCancelled() {
        adGatePendingAction = nil
        isAdGatePresented = false
    }

    func presentUnlockSheet(groupID: UUID) {
        unlockSheetGroupID = groupID
        isUnlockSheetPresented = true
    }

    // MARK: - 연장 불가 모드(기간 강력 잠금)

    private enum StrictBlockKind { case edit, delete }

    /// 연장 불가 시트 표시 대상 그룹(강제 unwrap 없이 항상 최신 groups에서 조회 — 확정 후 갱신 반영).
    var strictLockSheetGroup: ScreenTimeGroup? {
        guard let id = strictLockSheetGroupID else { return nil }
        return groups.first(where: { $0.id == id })
    }

    /// 스크린타임 권한 철회로 연장 불가 기간이 풀린 상태(복구 화면에서 강조·재승인 유도).
    var hasActiveStrictCommitment: Bool {
        groups.contains { $0.isStrictLockActive() }
    }

    /// 연장 불가 모드를 쓸 수 있는지(`ManageGroupsUseCase.isStrictLockEnabled` — 베타 기간엔 항상
    /// true, 정식 출시 때 구독 entitlement 판정이 들어올 자리). 닫히면 카드에 연장 불가 행을
    /// 그리지 않고 시트 진입도 거부한다. 단 **이미 걸린 기간은 게이트와 무관**하다(아래 참조).
    var isStrictLockFeatureEnabled: Bool = false

    /// 홈 상단 연장 불가 베타 배너가 금빛으로 발광해야 하는지(베타 노출 중 + 아직 첫 탭 전).
    var isStrictLockBetaBannerGlowing: Bool {
        isStrictLockFeatureEnabled && !hasSeenStrictLockBetaAnnouncement
    }

    /// 배너 첫 탭 — 발광을 끄고 그 상태를 영구 저장한다(다음 실행부터 발광 없음).
    func markStrictLockBetaAnnouncementSeen() {
        guard !hasSeenStrictLockBetaAnnouncement else { return }
        hasSeenStrictLockBetaAnnouncement = true
        userDefaults.set(true, forKey: Self.hasSeenStrictLockBetaAnnouncementKey)
    }

    /// 연장 불가 시트 열기. 게이트 열림 + applied + **유효 규칙** 그룹만 — `activateStrictLock`이 같은
    /// 검증으로 거부하므로, 무효 그룹(예: 적용 후 항목을 전부 해제)에서 진입을 허용하면 최종 확인까지
    /// 눌러도 확정이 조용히 실패해 "켜졌다"고 오인하게 된다. 이미 연장 불가 기간 중인 그룹(연장 진입)은
    /// 편집이 막혀 무효가 될 수 없으므로 검증을 건너뛴다.
    func presentStrictLockSheet(for group: ScreenTimeGroup) {
        guard isStrictLockFeatureEnabled, group.isApplied else { return }
        if !group.isStrictLockActive(),
           let reason = ScreenTimeGroupPolicy.invalidReason(for: group.policySnapshot) {
            alertMessage = GoldTimeAlertMessage(
                title: String(localized: "content.alert.strictCannotStart.title"),
                message: reason.userMessage
            )
            return
        }
        strictLockSheetGroupID = group.id
    }

    func setStrictLockSheetPresented(_ isPresented: Bool) {
        if !isPresented { strictLockSheetGroupID = nil }
    }

    /// 연장 불가 기간 시작·연장 확정. 성공 시 저장+sync(투영 스트립 덕에 모니터 재등록 없음)하고
    /// 분석 로깅 후 시트를 닫는다. 실패는 진입 검증 뒤라 드물지만(경합 등) **조용히 닫지 않고**
    /// 사유를 안내한다 — 사용자가 연장 불가 모드가 켜졌다고 오인하면 안 된다. alert은 시트가 닫히는
    /// 사이클과 겹치면 누락되므로 다음 런루프로 미룬다(Presentation/CLAUDE.md).
    /// 성공 alert도 같은 이유로 미루며, 잠금 피드백(소리·햅틱)을 그 자리에서 함께 재생한다 —
    /// 한 번 걸면 못 푸는 결정이라 확정 순간에 체감되는 신호가 있어야 한다.
    func confirmStrictLock(days: Int) {
        guard let id = strictLockSheetGroupID else { return }
        let wasActive = groups.first(where: { $0.id == id })?.isStrictLockActive() == true
        var updated = groups
        guard manageGroupsUseCase.activateStrictLock(id: id, days: days, in: &updated) else {
            let reason = groups.first(where: { $0.id == id })
                .flatMap { ScreenTimeGroupPolicy.invalidReason(for: $0.policySnapshot) }
            let failure = GoldTimeAlertMessage(
                title: String(localized: "content.alert.strictCannotStart.title"),
                message: reason?.userMessage ?? String(localized: "content.alert.strictCannotStart.message")
            )
            strictLockSheetGroupID = nil
            Task { @MainActor in self.alertMessage = failure }
            return
        }
        groups = updated
        successMessage = nil
        errorMessage = nil
        persistGroups()
        let group = groups.first(where: { $0.id == id })
        // 약정 기록(완주율 **분자**)과 시작 이벤트(**분모**)를 **같은 payload 조건에 묶어둔다** —
        // 분리하지 말 것. payload가 nil이면(applied 아님·ruleKind 없음 = `activateStrictLock`이
        // 이미 막아 도달 불가) 시작 이벤트가 안 나가는데, 약정만 따로 기록하면 나중에
        // `strict_lock_completed`가 짝 없이 전송돼 **완주율이 분자>분모로 깨진다**.
        // 둘 다 건너뛰면 그 잠금이 분석에서 통째로 빠질 뿐 비율은 성립한다.
        if let group, let payload = RuleGroupSnapshotAnalytics(group: group) {
            if let startedAt = group.strictStartedAt, let expiresAt = group.strictUntil {
                analyticsRepository.recordStrictLockCommitment(
                    groupID: group.id,
                    startedAt: startedAt,
                    expiresAt: expiresAt
                )
            }
            analyticsRepository.log(
                wasActive
                    ? .strictLockExtended(days: days, payload: payload)
                    : .strictLockStarted(days: days, payload: payload)
            )
        }
        strictLockSheetGroupID = nil
        let expiry = group?.strictUntil.map { goldTimeStrictLockedUntilText($0) } ?? ""
        let confirmed = wasActive
            ? GoldTimeAlertMessage(
                title: String(localized: "content.alert.strictExtended.title"),
                message: String(localized: "content.alert.strictExtended.message \(expiry)")
            )
            : GoldTimeAlertMessage(
                title: String(localized: "content.alert.strictStarted.title"),
                message: String(localized: "content.alert.strictStarted.message \(expiry)")
            )
        Task { @MainActor in
            LockFeedback.play()
            self.alertMessage = confirmed
        }
    }

    /// 스크린타임 권한 복구 화면이 뜰 때 호출. 연장 불가 기간이 살아 있으면 1회만 철회 감지를 로깅한다.
    func handleScreenTimeRecoveryAppear() {
        guard hasActiveStrictCommitment, !didLogStrictRevoke else { return }
        didLogStrictRevoke = true
        analyticsRepository.discardStrictLockCommitments(
            groupIDs: groups.filter { $0.isStrictLockActive() }.map(\.id)
        )
        analyticsRepository.log(.strictLockRevokeDetected)
    }

    /// 연장 불가 모드 편집·삭제 차단 안내 alert. 만료 날짜(%@)는 공용 포매터로 포맷한다.
    private func strictBlockedAlert(for group: ScreenTimeGroup, kind: StrictBlockKind) -> GoldTimeAlertMessage {
        let expiry = group.strictUntil.map { goldTimeStrictLockedUntilText($0) } ?? ""
        let message: String
        switch kind {
        case .edit:
            message = String(localized: "content.alert.strictBlocked.edit \(expiry)")
        case .delete:
            message = String(localized: "content.alert.strictBlocked.delete \(expiry)")
        }
        return GoldTimeAlertMessage(
            title: String(localized: "content.alert.strictBlocked.title"),
            message: message
        )
    }

    func reconnectMonitoring() {
        guard !isReconnecting else { return }
        Task { @MainActor in
            isReconnecting = true
            defer { isReconnecting = false }
            do {
                try syncProtectionUseCase.reconnectMonitoring()
                refreshDashboardState()
                alertMessage = GoldTimeAlertMessage(title: String(localized: "content.alert.reconnected.title"), message: String(localized: "content.alert.reconnected.message"))
            } catch {
                refreshDashboardState()
                alertMessage = GoldTimeAlertMessage(title: String(localized: "content.alert.reconnectFailed.title"), message: error.localizedDescription)
            }
        }
    }

    private func persistGroups(shouldSyncProtection: Bool = true) {
        if shouldSyncProtection {
            syncProtectionRules()
        } else {
            manageGroupsUseCase.persist(groups)
            groups = manageGroupsUseCase.currentGroups()
            refreshDashboardState()
            updateCohortUserProperties()
        }
    }

    private func updateGroup(
        _ id: UUID,
        shouldSyncProtection: Bool = true,
        update: (inout [ScreenTimeGroup]) -> Void
    ) {
        update(&groups)
        successMessage = nil
        errorMessage = nil
        persistGroups(shouldSyncProtection: shouldSyncProtection)
    }

    private func syncProtectionRules() {
        do {
            try manageGroupsUseCase.persistAndSync(groups)
            groups = manageGroupsUseCase.currentGroups()
            errorMessage = nil
            let state = loadDashboardUseCase.refresh(groups: groups)
            isMonitoring = state.isDailyMonitoringEnabled
            applyDashboardState(state)
            updateCohortUserProperties()
        } catch {
            successMessage = nil
            errorMessage = String(localized: "content.autoApplyFailed \(error.localizedDescription)")
            refreshDashboardState()
            // persistAndSync는 모니터 등록이 실패해도 그룹을 먼저 저장하므로,
            // 저장된 규칙 조합 user property는 최신 상태로 갱신한다.
            updateCohortUserProperties()
        }
    }

    /// 규칙/연장 불가 변경 직후에도 Firebase user property가 다음 이벤트보다 먼저 최신 구성으로
    /// 갱신되게 한다. Firebase에는 식별자·그룹명 없이 집계된 profile만 보낸다.
    private func updateCohortUserProperties() {
        guard isAuthorized else { return }
        // [삭제 예정 — TODO.md] 1.3.0에서 group_snapshot과 중복이라 폐기한 사용자 속성의 기존 값을
        // 지운다. 같은 줄이 `AppLifecycleViewModel.updateCohortUserProperties`에도 있다
        // (그쪽은 권한 guard 밖) — 지울 때 함께 지운다.
        analyticsRepository.setUserProperty(nil, for: "active_group_count")
        for entry in UserCohortProperties(groups: groups).entries {
            analyticsRepository.setUserProperty(entry.value, for: entry.name)
        }
    }

    private func isAppliedGroup(_ id: UUID) -> Bool {
        groups.first(where: { $0.id == id })?.isApplied == true
    }

    private func applyDashboardState(_ state: DashboardState) {
        isShieldActive = state.isShieldActive
        oneMinuteRemaining = state.oneMinuteRemaining
        oneMinuteDailyLimit = state.oneMinuteDailyLimit
        shieldOverrideUntil = state.shieldOverrideUntil
        todayStats = state.todayStats
        statsReport = state.statsReport
        adFreeStreakDays = state.adFreeStreakDays
        maxAdFreeStreakDays = state.maxAdFreeStreakDays
        isMonitoring = state.isDailyMonitoringEnabled
        lockedGroupIDs = state.lockedGroupIDs
        overrideGroupIDs = state.overrideGroupIDs
        validGroupIDs = state.validGroupIDs
        untrackedGroupIDs = state.untrackedGroupIDs
        overrideUntilByGroupID = state.overrideUntilByGroupID
        usedTimeByGroupID = state.usedTimeByGroupID
        overrideBaselineUsedTimeByGroupID = state.overrideBaselineUsedTimeByGroupID
        overrideGrantedMinutesByGroupID = state.overrideGrantedMinutesByGroupID
        cooldownEndByGroupID = state.cooldownEndByGroupID
    }

    private func applyScreenTimeAuthorization(
        _ authorized: Bool,
        presentsRecoveryIfMissing: Bool = false
    ) {
        isAuthorized = authorized
        if authorized {
            isScreenTimeRecoveryPresented = false
            screenTimeRecoveryErrorMessage = nil
            // 권한이 복구되면 다음 철회를 다시 관측할 수 있도록 로깅 플래그를 리셋한다.
            didLogStrictRevoke = false
        } else if presentsRecoveryIfMissing && hasCompletedInitialHomeEntry {
            isScreenTimeRecoveryPresented = true
        }
    }

    private func completeScreenTimeAuthorizationRestore() {
        applyScreenTimeAuthorization(true)
        markInitialHomeEntryIfReady()
        groups = manageGroupsUseCase.currentGroups()
        syncProtectionRules()
    }

    private func presentScreenTimeRecovery() {
        screenTimeRecoveryErrorMessage = String(localized: "content.recovery.errorMessage")
        applyScreenTimeAuthorization(false, presentsRecoveryIfMissing: true)
        refreshDashboardState()
    }

    private func markInitialHomeEntryIfReady() {
        // 알림은 선택 권한이므로 스크린타임 권한만 확보되면 홈 진입을 확정한다.
        guard isAuthorized, !hasCompletedInitialHomeEntry else { return }
        // 단, 온보딩을 아직 진행 중이면(저장된 단계 존재) 완료 처리하지 않는다.
        // 스크린타임 허용 직후 알림/광고 단계에서 앱을 종료하고 재실행해도
        // 권한만 보고 홈으로 건너뛰지 않도록, 끝까지 마칠 때까지 온보딩을 유지한다.
        if userDefaults.string(forKey: OnboardingViewModel.savedStepKey) != nil { return }
        hasCompletedInitialHomeEntry = true
        userDefaults.set(true, forKey: Self.hasCompletedInitialHomeEntryKey)
    }
}
