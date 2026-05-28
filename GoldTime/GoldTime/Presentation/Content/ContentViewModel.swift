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
        let clamped = min(group.dailyLimitMinutes, 6 * 60 + 55)
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
        updateGroupLimit(id, minutes: limitPickerHours * 60 + limitPickerMinutes)
        limitPickerGroupID = nil
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

    func requestDeleteGroup(_ id: UUID) {
        guard lockedGroupIDs.contains(id) else {
            deleteGroup(id)
            return
        }
        adGatePendingAction = { [weak self] in self?.deleteGroup(id) }
        adGateFallbackLabel = "그래도 삭제하기"
        isAdGatePresented = true
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
