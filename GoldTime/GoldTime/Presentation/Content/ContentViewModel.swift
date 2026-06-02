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
    let id = UUID()
    let groupID: UUID
    let groupName: String
    let minutes: Int
    let usedMinutes: Int
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
    var shouldShowInitialOnboarding: Bool { !hasCompletedInitialHomeEntry && !isFullyAuthorized }
    var shouldShowNotificationOnboarding: Bool {
        hasCompletedInitialHomeEntry && isAuthorized && !isNotificationAuthorized
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
    private var stagedLimitLockWarning: LimitLockWarning?
    private var pendingDeletedGroupName: String?
    var isReconnecting = false
    var isScreenTimeRecoveryPresented = false
    var isRequestingScreenTimeAuthorization = false
    var screenTimeRecoveryErrorMessage: String?

    var limitPickerGroupID: UUID?
    var limitPickerHours = 0
    var limitPickerMinutes = 30

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
    var overrideUntilByGroupID: [UUID: Date] = [:]
    var usedTimeByGroupID: [UUID: Int] = [:]
    var overrideBaselineUsedTimeByGroupID: [UUID: Int] = [:]
    var overrideGrantedMinutesByGroupID: [UUID: Int] = [:]
    var unlockSheetGroupID: UUID? = nil
    var isUnlockSheetPresented = false

    var isAdGatePresented = false
    var adGateFallbackLabel: String = ""
    private var adGatePendingAction: (() -> Void)? = nil

    private let manageGroupsUseCase: ManageGroupsUseCase
    private let syncProtectionUseCase: SyncProtectionUseCase
    private let loadDashboardUseCase: LoadDashboardUseCase
    private let authorizeUseCase: AuthorizeUseCase
    private let userDefaults: UserDefaults
    private var authorizationObservation: AuthorizationObservation?

    init(
        manageGroupsUseCase: ManageGroupsUseCase? = nil,
        syncProtectionUseCase: SyncProtectionUseCase? = nil,
        loadDashboardUseCase: LoadDashboardUseCase? = nil,
        authorizeUseCase: AuthorizeUseCase? = nil,
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
            oldestStatDate: statsRepo.oldestStatDate
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

    var isLimitPickerPresented: Bool {
        limitPickerGroupID != nil
    }

    func setLimitPickerPresented(_ isPresented: Bool) {
        if !isPresented {
            limitPickerGroupID = nil
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

    func updateGroupLimit(_ id: UUID, minutes: Int) {
        updateGroup(id) { groups in
            manageGroupsUseCase.updateLimit(id: id, minutes: minutes, in: &groups)
        }
    }

    func presentPicker(for group: ScreenTimeGroup) {
        pickerGroupID = group.id
        pickerSelection = group.selection.supportedTokenSelection
        isPickerPresented = true
    }

    func presentLimitPicker(for group: ScreenTimeGroup) {
        let clamped = min(group.dailyLimitMinutes, 5 * 60 + 55)
        limitPickerHours = clamped / 60
        let rawMinutes = clamped % 60
        limitPickerMinutes = (rawMinutes / 5) * 5
        limitPickerGroupID = group.id
    }

    func commitPickerSelection() {
        guard let groupID = pickerGroupID else { return }
        let selection = pickerSelection
        updateGroup(groupID) { groups in
            manageGroupsUseCase.updateSelection(id: groupID, selection: selection, in: &groups)
        }
    }

    func commitLimitPickerSelection() {
        guard let id = limitPickerGroupID else { return }
        let minutes = limitPickerHours * 60 + limitPickerMinutes
        let used = usedTimeByGroupID[id] ?? 0

        // 이미 사용한 시간보다 작은 한도면 즉시 잠긴다(syncDailyMonitoring의 used >= limit 분기).
        // 바로 적용하지 말고, 시트가 닫힌 뒤 확인 경고를 띄운다.
        if used > 0 && minutes <= used {
            let name = groups.first(where: { $0.id == id })?.name ?? "이 그룹"
            stagedLimitLockWarning = LimitLockWarning(
                groupID: id,
                groupName: name,
                minutes: minutes,
                usedMinutes: used
            )
            limitPickerGroupID = nil
            return
        }

        updateGroupLimit(id, minutes: minutes)
        limitPickerGroupID = nil
    }

    /// 한도 피커 시트가 닫힌 뒤 호출. 즉시 잠금 경고가 대기 중이면 alert로 띄운다
    /// (시트 dismiss와 alert를 동시에 표시하면 alert가 누락될 수 있어 순서를 분리).
    func handleLimitPickerDismiss() {
        guard let staged = stagedLimitLockWarning else { return }
        stagedLimitLockWarning = nil
        pendingLimitLockWarning = staged
    }

    // warning을 인자로 받는다: .alert(item:)이 버튼 액션 전에 바인딩을 nil로 만들어
    // 상태에서 다시 읽으면 nil이 되기 때문(early-return 버그 방지).
    func confirmLimitLockChange(_ warning: LimitLockWarning) {
        pendingLimitLockWarning = nil
        updateGroupLimit(warning.groupID, minutes: warning.minutes)
    }

    func cancelLimitLockChange() {
        pendingLimitLockWarning = nil
    }

    func requestPickerPresentation(for group: ScreenTimeGroup) {
        guard lockedGroupIDs.contains(group.id) else {
            presentPicker(for: group)
            return
        }
        adGatePendingAction = { [weak self] in self?.presentPicker(for: group) }
        adGateFallbackLabel = "그래도 편집하기"
        isAdGatePresented = true
    }

    func requestLimitPickerPresentation(for group: ScreenTimeGroup) {
        guard lockedGroupIDs.contains(group.id) else {
            presentLimitPicker(for: group)
            return
        }
        adGatePendingAction = { [weak self] in self?.presentLimitPicker(for: group) }
        adGateFallbackLabel = "그래도 변경하기"
        isAdGatePresented = true
    }

    func requestDeleteGroup(_ id: UUID) {
        let name = groups.first(where: { $0.id == id })?.name ?? "이 그룹"
        guard lockedGroupIDs.contains(id) else {
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
            syncProtectionRules()
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

    private func syncProtectionRules() {
        do {
            try manageGroupsUseCase.persistAndSync(groups)
            groups = manageGroupsUseCase.currentGroups()
            errorMessage = nil
            let state = loadDashboardUseCase.refresh(groups: groups)
            isMonitoring = state.isDailyMonitoringEnabled
            applyDashboardState(state)
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
        overrideUntilByGroupID = state.overrideUntilByGroupID
        usedTimeByGroupID = state.usedTimeByGroupID
        overrideBaselineUsedTimeByGroupID = state.overrideBaselineUsedTimeByGroupID
        overrideGrantedMinutesByGroupID = state.overrideGrantedMinutesByGroupID
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
        guard isFullyAuthorized, !hasCompletedInitialHomeEntry else { return }
        hasCompletedInitialHomeEntry = true
        userDefaults.set(true, forKey: Self.hasCompletedInitialHomeEntryKey)
    }
}
