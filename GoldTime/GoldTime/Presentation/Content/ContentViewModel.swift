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
    var selectedTab = GoldTimeTab.home
    var isAuthorized: Bool
    var groups: [ScreenTimeGroup] = []
    var pickerSelection = FamilyActivitySelection()
    var pickerGroupID: UUID?
    var isPickerPresented = false
    var isMonitoring = false
    var errorMessage: String?
    var successMessage: String?
    var alertMessage: GoldTimeAlertMessage?
    var isResetProtectionConfirmationPresented = false

    var limitPickerGroupID: UUID?
    var limitPickerHours = 0
    var limitPickerMinutes = 30

    var isShieldActive: Bool
    var oneMinuteRemaining: Int
    var shieldOverrideUntil: Date?
    var todayStats: DailyStats
    var weeklyStats: [DailyStats]
    var lockedGroupIDs: Set<UUID> = []
    var overrideGroupIDs: Set<UUID> = []
    var validGroupIDs: Set<UUID> = []
    var overrideUntilByGroupID: [UUID: Date] = [:]

    private let manageGroupsUseCase: ManageGroupsUseCase
    private let syncProtectionUseCase: SyncProtectionUseCase
    private let loadDashboardUseCase: LoadDashboardUseCase
    private let authorizeUseCase: AuthorizeUseCase
    private var authorizationObservation: AuthorizationObservation?

    init(
        manageGroupsUseCase: ManageGroupsUseCase? = nil,
        syncProtectionUseCase: SyncProtectionUseCase? = nil,
        loadDashboardUseCase: LoadDashboardUseCase? = nil,
        authorizeUseCase: AuthorizeUseCase? = nil
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

        isAuthorized = self.authorizeUseCase.isAuthorized
        isShieldActive = shieldRepo.isShieldActive
        oneMinuteRemaining = shieldRepo.oneMinuteRemaining
        shieldOverrideUntil = shieldRepo.currentShieldOverrideUntil
        todayStats = statsRepo.todayStats
        weeklyStats = statsRepo.lastSevenDayStats()

        authorizationObservation = self.authorizeUseCase.observeAuthorizationChanges { [weak self] isAuthorized in
            self?.isAuthorized = isAuthorized
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
        isAuthorized = authorizeUseCase.isAuthorized
    }

    func loadState() {
        refreshAuthorization()
        syncProtectionUseCase.prepareForAppActivation()
        groups = manageGroupsUseCase.currentGroups()
        syncProtectionRules()
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
        pickerSelection = group.selection
        isPickerPresented = true
    }

    func presentLimitPicker(for group: ScreenTimeGroup) {
        limitPickerHours = group.dailyLimitMinutes / 60
        limitPickerMinutes = group.dailyLimitMinutes % 60
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

    func requestResetProtection() {
        isResetProtectionConfirmationPresented = true
    }

    func resetProtectionState() {
        do {
            try syncProtectionUseCase.resetProtectionState()
            groups = manageGroupsUseCase.currentGroups()
            errorMessage = nil
            successMessage = "보호 상태를 초기화하고 유효한 그룹을 다시 적용했어요."
            refreshDashboardState()
        } catch {
            successMessage = nil
            errorMessage = "전체 보호 초기화 실패: \(error.localizedDescription)"
            refreshDashboardState()
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
        shieldOverrideUntil = state.shieldOverrideUntil
        todayStats = state.todayStats
        weeklyStats = state.weeklyStats
        isMonitoring = state.isDailyMonitoringEnabled
        lockedGroupIDs = state.lockedGroupIDs
        overrideGroupIDs = state.overrideGroupIDs
        validGroupIDs = state.validGroupIDs
        overrideUntilByGroupID = state.overrideUntilByGroupID
    }
}
