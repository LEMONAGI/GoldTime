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

    /// 자정 직전(23:45+)이라 편집해도 사용량 추적이 자정까지 불가능할 때 편집 상세에 띄울 안내.
    /// 일일 한도·쿨다운 상세에서만 노출한다(시간대별 차단은 영향 없음 — View에서 분기).
    var nearMidnightEditNotice: String? {
        guard manageGroupsUseCase.isNearMidnightEditCutoff() else { return nil }
        return "23:45부터는 사용량 추적이 어려워요. 지금 바꾼 규칙은 00:00부터 다시 정확히 적용됩니다."
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

        do {
            try await authorizeUseCase.requestScreenTime()
            applyScreenTimeAuthorization(true)
            markInitialHomeEntryIfReady()
            groups = manageGroupsUseCase.currentGroups()
            syncProtectionRules()
        } catch {
            applyScreenTimeAuthorization(false)
            screenTimeRecoveryErrorMessage = "스크린타임 권한을 다시 허용해야 앱 한도를 적용할 수 있어요."
            refreshDashboardState()
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
            alertMessage = GoldTimeAlertMessage(title: "그룹 제한", message: error.localizedDescription)
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
        ruleEditorGroupID = group.id
    }

    func commitPickerSelection() {
        guard let groupID = pickerGroupID else { return }
        let selection = pickerSelection
        updateGroup(groupID) { groups in
            manageGroupsUseCase.updateSelection(id: groupID, selection: selection, in: &groups)
        }
    }

    /// 규칙 편집기의 확인. 선택된 규칙 종류에 따라 일일 한도/시간대 차단을 각각 적용한다.
    func commitRuleSelection() {
        switch ruleEditorSelectedKind {
        case .dailyLimit:
            commitDailyLimitRule()
        case .timeWindows:
            commitTimeWindowsRule()
        case .cooldown:
            commitCooldownRule()
        }
    }

    /// 그룹이 현재 자유롭게 사용 가능한(잠김X·휴식X·override X) 상태인지.
    /// 편집으로 "즉시 잠금/휴식 진입" 확인 알럿을 띄울지 판단하는 데 쓴다(전환이 실제로 일어날 때만).
    private func isGroupCurrentlyOpen(_ id: UUID) -> Bool {
        !lockedGroupIDs.contains(id) && !overrideGroupIDs.contains(id)
    }

    private func commitCooldownRule() {
        guard let id = ruleEditorGroupID else { return }
        let usage = ruleEditorCooldownUsageMinutes
        let duration = ruleEditorCooldownDurationMinutes

        // 뷰에서 저장 버튼을 막아도, VM에서 한 번 더 검증한다.
        if let reason = CooldownPolicy.firstInvalidReason(usageMinutes: usage, cooldownMinutes: duration) {
            alertMessage = GoldTimeAlertMessage(title: "쿨다운 확인", message: reason.userMessage)
            return
        }

        let used = usedTimeByGroupID[id] ?? 0
        // 이미 사용한 시간보다 작은 예산이면 즉시 휴식에 들어간다(일일 한도 즉시 잠금과 동일 패턴).
        // 바로 적용하지 말고, 시트가 닫힌 뒤 확인 경고를 띄운다.
        // 단, 이미 잠김/휴식/override 중이면 새 전환이 아니므로 경고를 생략하고 바로 적용한다.
        if isGroupCurrentlyOpen(id) && used > 0 && usage <= used {
            let name = groups.first(where: { $0.id == id })?.name ?? "이 그룹"
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
                title: "변경 안내",
                message: "변경된 설정은 다음 주기부터 적용돼요."
            )
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
            let name = groups.first(where: { $0.id == id })?.name ?? "이 그룹"
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
        ruleEditorGroupID = nil
    }

    private func commitTimeWindowsRule() {
        guard let id = ruleEditorGroupID else { return }
        let windows = ruleEditorTimeWindows

        // 뷰에서 저장 버튼을 막아도, VM에서 한 번 더 검증한다.
        if let reason = TimeWindowPolicy.firstInvalidReason(for: windows) {
            alertMessage = GoldTimeAlertMessage(title: "시간대 확인", message: reason.userMessage)
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
        adGateFallbackLabel = "그래도 편집하기"
        isAdGatePresented = true
    }

    func requestRuleEditorPresentation(for group: ScreenTimeGroup) {
        guard isEditRestricted(group.id) else {
            presentRuleEditor(for: group)
            return
        }
        adGatePendingAction = { [weak self] in self?.presentRuleEditor(for: group) }
        adGateFallbackLabel = "그래도 변경하기"
        isAdGatePresented = true
    }

    func requestDeleteGroup(_ id: UUID) {
        let name = groups.first(where: { $0.id == id })?.name ?? "이 그룹"
        guard isEditRestricted(id) else {
            deleteGroup(id)
            presentDeletionCompletedAlert(groupName: name)
            return
        }
        adGatePendingAction = { [weak self] in
            self?.deleteGroup(id)
            self?.pendingDeletedGroupName = name
        }
        adGateFallbackLabel = "그래도 삭제하기"
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
        let message = GoldTimeAlertMessage(title: "삭제 완료", message: "‘\(groupName)’ 그룹을 삭제했어요.")
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
            alertMessage = GoldTimeAlertMessage(title: "적용할 수 없어요", message: reason.userMessage)
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
        let ruleKind = groups.first { $0.id == confirmation.groupID }?.ruleKind?.rawValue ?? "unknown"
        analyticsRepository.log(.groupApplied(ruleKind: ruleKind))
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
                alertMessage = GoldTimeAlertMessage(title: "재연결 완료", message: "스크린 타임이 다시 연결됐어요.")
            } catch {
                refreshDashboardState()
                alertMessage = GoldTimeAlertMessage(title: "재연결 실패", message: error.localizedDescription)
            }
        }
    }

    private func persistGroups(shouldSyncProtection: Bool = true) {
        if shouldSyncProtection {
            // 사용자가 그룹을 편집해 모니터링을 재적용하는 경로. foreground 진입 경로
            // (requestScreenTimeAuthorizationOnEntry)와 달리 분석 이벤트를 남긴다.
            syncProtectionRules(logMonitoringSync: true)
        } else {
            manageGroupsUseCase.persist(groups)
            groups = manageGroupsUseCase.currentGroups()
            refreshDashboardState()
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

    private func syncProtectionRules(logMonitoringSync: Bool = false) {
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
        } catch {
            successMessage = nil
            errorMessage = "자동 적용 실패: \(error.localizedDescription)"
            refreshDashboardState()
        }
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

    private func applyScreenTimeAuthorization(_ authorized: Bool) {
        isAuthorized = authorized
        if authorized {
            isScreenTimeRecoveryPresented = false
            screenTimeRecoveryErrorMessage = nil
        } else if hasCompletedInitialHomeEntry {
            isScreenTimeRecoveryPresented = true
        }
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
