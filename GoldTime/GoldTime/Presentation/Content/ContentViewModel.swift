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

    var selectedTab = GoldTimeTab.home
    var isAuthorized: Bool
    var isNotificationAuthorized: Bool = false
    var isCheckingPermissions: Bool = true
    var isFullyAuthorized: Bool { isAuthorized && isNotificationAuthorized }
    var hasCompletedInitialHomeEntry: Bool
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
            analyticsRepository.log(.groupCreated(groupCount: groups.count))
            successMessage = nil
            errorMessage = nil
        } catch {
            alertMessage = GoldTimeAlertMessage(title: String(localized: "content.alert.groupLimit.title"), message: error.localizedDescription)
        }
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        successMessage = nil
        errorMessage = nil
        persistGroups()
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
        let monitoringRegistrationGroupID = monitoringRegistrationGroupIDIfApplied(groupID)
        updateGroup(groupID, monitoringRegistrationGroupID: monitoringRegistrationGroupID) { groups in
            manageGroupsUseCase.updateSelection(id: groupID, selection: selection, in: &groups)
        }
    }

    /// 규칙 편집기의 확인. 요일별 모드면 요일 규칙을, 아니면 선택된 규칙 종류를 각각 적용한다.
    func commitRuleSelection() {
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
        logRuleChangeToWeekdayIfNeeded(id: id, todayRule: todayRule, used: used)

        // 즉시 잠금 경고는 오늘 투영 규칙 기준(일일/쿨다운이고 새 예산 <= 사용량). 시트가 닫힌 뒤 띄운다.
        // 이미 잠김/휴식/override 중이면 새 전환이 아니므로 경고를 생략하고 바로 적용한다.
        if isGroupCurrentlyOpen(id), used > 0,
           let warning = weekdayImmediateLockWarning(id: id, todayRule: todayRule, used: used, rules: rules) {
            stagedLimitLockWarning = warning
            ruleEditorGroupID = nil
            return
        }

        applyWeekdayRules(id: id, rules: rules)

        // 자정 근처 안내: 오늘 투영 kind가 daily/cooldown일 때만(측정창 영향).
        let todayTracked = todayRule.kind == .dailyLimit || todayRule.kind == .cooldown
        if monitoringRegistrationGroupIDIfApplied(id) != nil && todayTracked
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
        let monitoringRegistrationGroupID = monitoringRegistrationGroupIDIfApplied(id)
        updateGroup(id, monitoringRegistrationGroupID: monitoringRegistrationGroupID) { groups in
            manageGroupsUseCase.updateWeekdayRules(id: id, rules: rules, in: &groups)
        }
    }

    /// 그룹이 현재 자유롭게 사용 가능한(잠김X·휴식X·override X) 상태인지.
    /// 편집으로 "즉시 잠금/휴식 진입" 확인 알럿을 띄울지 판단하는 데 쓴다(전환이 실제로 일어날 때만).
    private func isGroupCurrentlyOpen(_ id: UUID) -> Bool {
        !lockedGroupIDs.contains(id) && !overrideGroupIDs.contains(id)
    }

    /// 그룹의 현재 규칙 표기(`rule_changed` from/to 값). 요일별 모드면 "weekday", 아니면 base 규칙
    /// rawValue, 규칙 미선택이면 nil. 요일별 ↔ 단일 전환도 관찰 가능하게 한다.
    private func ruleDescriptor(for group: ScreenTimeGroup?) -> String? {
        guard let group else { return nil }
        if group.usesWeekdayRules { return "weekday" }
        return group.ruleKind?.rawValue
    }

    /// 모드 전환(규칙 변경)을 관찰용으로 기록한다(`rule_changed`). 같은 규칙 내 값 변경은 제외.
    /// apply/early-return 이전(전환 직전 상태)에 호출해야 was_locked·used가 정확하다.
    /// `effectiveLimit`: 일일 한도/쿨다운 예산(분). timeWindows는 측정창과 무관하므로 미사용(0 전달).
    private func logRuleChangeIfNeeded(id: UUID, to: GroupRuleKind, effectiveLimit: Int) {
        guard let old = ruleDescriptor(for: groups.first(where: { $0.id == id })), old != to.rawValue else { return }
        let used = usedTimeByGroupID[id] ?? 0
        let causedLock = (to == .dailyLimit || to == .cooldown) && used >= effectiveLimit
        analyticsRepository.log(.ruleChanged(
            from: old,
            to: to.rawValue,
            wasLocked: !isGroupCurrentlyOpen(id),
            usedBucket: RuleAnalyticsPayload.usedBucket(used),
            causedLock: causedLock
        ))
    }

    /// 요일별 모드로의 전환을 기록한다(`rule_changed`, to = "weekday"). 이미 요일별 모드면 제외.
    /// causedLock은 오늘 투영 규칙이 즉시 잠김을 유발하는지로 판단한다.
    private func logRuleChangeToWeekdayIfNeeded(id: UUID, todayRule: DayRule, used: Int) {
        guard let old = ruleDescriptor(for: groups.first(where: { $0.id == id })), old != "weekday" else { return }
        let causedLock = (todayRule.kind == .dailyLimit && todayRule.dailyLimitMinutes <= used)
            || (todayRule.kind == .cooldown && todayRule.cooldownUsageMinutes <= used)
        analyticsRepository.log(.ruleChanged(
            from: old,
            to: "weekday",
            wasLocked: !isGroupCurrentlyOpen(id),
            usedBucket: RuleAnalyticsPayload.usedBucket(used),
            causedLock: causedLock
        ))
    }

    /// 자정 직전(23:45+) 적용·수정 직후 안내 alert. 모니터 등록이 막혀 규칙이 00:00부터
    /// 적용되는 상황을 알린다. 일일 한도·쿨다운만 — 시간대 차단은 측정창과 무관해 제외한다.
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
        logRuleChangeIfNeeded(id: id, to: .cooldown, effectiveLimit: usage)
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

        applyCooldownRule(id: id, usage: usage, duration: duration)
        if settingsChangedWhileResting {
            stagedRuleEditInfo = GoldTimeAlertMessage(
                title: String(localized: "content.alert.changeNotice.title"),
                message: String(localized: "content.alert.changeNotice.message")
            )
        } else if monitoringRegistrationGroupIDIfApplied(id) != nil
            && manageGroupsUseCase.isNearMidnightMonitorTooShort() {
            stagedRuleEditInfo = nearMidnightApplyNotice
        }
        ruleEditorGroupID = nil
    }

    private func applyCooldownRule(id: UUID, usage: Int, duration: Int) {
        let monitoringRegistrationGroupID = monitoringRegistrationGroupIDIfApplied(id)
        updateGroup(id, monitoringRegistrationGroupID: monitoringRegistrationGroupID) { groups in
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
        logRuleChangeIfNeeded(id: id, to: .dailyLimit, effectiveLimit: minutes)

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

        applyDailyLimitRule(id: id, minutes: minutes)
        if monitoringRegistrationGroupIDIfApplied(id) != nil
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

        logRuleChangeIfNeeded(id: id, to: .timeWindows, effectiveLimit: 0)

        // 규칙을 timeWindows로 바꿔도 dailyLimitMinutes는 그대로 보존(되돌릴 때 재사용).
        let monitoringRegistrationGroupID = monitoringRegistrationGroupIDIfApplied(id)
        updateGroup(id, monitoringRegistrationGroupID: monitoringRegistrationGroupID) { groups in
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
        let monitoringRegistrationGroupID = monitoringRegistrationGroupIDIfApplied(id)
        updateGroup(id, monitoringRegistrationGroupID: monitoringRegistrationGroupID) { groups in
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

    /// 적용(commit)된 그룹은 우회 방지를 위해 편집/한도/삭제 전에 광고 게이트를 거친다.
    /// applied는 잠금/연장 상태를 모두 포함(applied ⊃ locked ∪ override)하므로 더 엄격한 기준이다.
    /// draft(미적용) 그룹은 자유롭게 수정·삭제할 수 있도록 게이트 없음.
    private func isEditRestricted(_ id: UUID) -> Bool {
        groups.first(where: { $0.id == id })?.isApplied ?? false
    }

    func requestPickerPresentation(for group: ScreenTimeGroup) {
        guard isEditRestricted(group.id) else {
            presentPicker(for: group)
            return
        }
        adGatePendingAction = { [weak self] in self?.presentPicker(for: group) }
        adGateFallbackLabel = String(localized: "content.adGate.edit")
        isAdGatePresented = true
    }

    func requestRuleEditorPresentation(for group: ScreenTimeGroup) {
        guard isEditRestricted(group.id) else {
            presentRuleEditor(for: group)
            return
        }
        adGatePendingAction = { [weak self] in self?.presentRuleEditor(for: group) }
        adGateFallbackLabel = String(localized: "content.adGate.change")
        isAdGatePresented = true
    }

    func requestDeleteGroup(_ id: UUID) {
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
        updateGroup(confirmation.groupID, monitoringRegistrationGroupID: confirmation.groupID) { groups in
            manageGroupsUseCase.markApplied(id: confirmation.groupID, in: &groups)
        }
        if let group = groups.first(where: { $0.id == confirmation.groupID }) {
            analyticsRepository.log(.groupApplied(payload: RuleAnalyticsPayload(group: group)))
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

    private func persistGroups(
        shouldSyncProtection: Bool = true,
        monitoringRegistrationGroupID: UUID? = nil
    ) {
        if shouldSyncProtection {
            // 사용자가 그룹을 편집해 모니터링을 재적용하는 경로. foreground 진입 경로
            // (requestScreenTimeAuthorizationOnEntry)와 달리 분석 이벤트를 남긴다.
            syncProtectionRules(
                logMonitoringSync: true,
                monitoringRegistrationGroupID: monitoringRegistrationGroupID
            )
        } else {
            manageGroupsUseCase.persist(groups)
            groups = manageGroupsUseCase.currentGroups()
            refreshDashboardState()
        }
    }

    private func updateGroup(
        _ id: UUID,
        shouldSyncProtection: Bool = true,
        monitoringRegistrationGroupID: UUID? = nil,
        update: (inout [ScreenTimeGroup]) -> Void
    ) {
        update(&groups)
        successMessage = nil
        errorMessage = nil
        persistGroups(
            shouldSyncProtection: shouldSyncProtection,
            monitoringRegistrationGroupID: monitoringRegistrationGroupID
        )
    }

    private func syncProtectionRules(
        logMonitoringSync: Bool = false,
        monitoringRegistrationGroupID: UUID? = nil
    ) {
        do {
            try manageGroupsUseCase.persistAndSync(groups)
            groups = manageGroupsUseCase.currentGroups()
            errorMessage = nil
            let state = loadDashboardUseCase.refresh(groups: groups)
            isMonitoring = state.isDailyMonitoringEnabled
            applyDashboardState(state)
            if logMonitoringSync {
                let appliedCount = groups.filter { $0.isApplied }.count
                analyticsRepository.log(.monitoringSynced(appliedGroupCount: appliedCount))
            }
            logRuleMonitoringRegisteredIfNeeded(
                groupID: monitoringRegistrationGroupID,
                validGroupIDs: state.validGroupIDs
            )
        } catch {
            successMessage = nil
            errorMessage = String(localized: "content.autoApplyFailed \(error.localizedDescription)")
            refreshDashboardState()
        }
    }

    private func monitoringRegistrationGroupIDIfApplied(_ id: UUID) -> UUID? {
        groups.first(where: { $0.id == id })?.isApplied == true ? id : nil
    }

    private func logRuleMonitoringRegisteredIfNeeded(groupID: UUID?, validGroupIDs: Set<UUID>) {
        guard let groupID,
              validGroupIDs.contains(groupID),
              let group = groups.first(where: { $0.id == groupID }) else { return }
        analyticsRepository.log(.ruleMonitoringRegistered(payload: RuleAnalyticsPayload(group: group)))
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
