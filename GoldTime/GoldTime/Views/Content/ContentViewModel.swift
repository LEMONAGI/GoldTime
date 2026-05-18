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
    var groups: [SharedStore.ScreenTimeGroup] = []
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
    var todayStats: SharedStore.DailyStats
    var weeklyStats: [SharedStore.DailyStats]

    private var store: any GoldTimeStoreProviding
    private let screenTimeManager: any ScreenTimeManaging
    private let authorization: any AuthorizationProviding

    init(
        store: (any GoldTimeStoreProviding)? = nil,
        screenTimeManager: (any ScreenTimeManaging)? = nil,
        authorization: (any AuthorizationProviding)? = nil
    ) {
        let resolvedStore = store ?? GoldTimeStoreAdapter()
        let resolvedAuthorization = authorization ?? AuthorizationService.shared
        self.store = resolvedStore
        self.screenTimeManager = screenTimeManager ?? ScreenTimeManagerAdapter()
        self.authorization = resolvedAuthorization
        isAuthorized = resolvedAuthorization.isAuthorized
        isShieldActive = resolvedStore.isShieldActive
        oneMinuteRemaining = resolvedStore.oneMinuteRemaining
        shieldOverrideUntil = resolvedStore.currentShieldOverrideUntil
        todayStats = resolvedStore.todayStats
        weeklyStats = resolvedStore.lastSevenDayStats()
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
        authorization.refresh()
        isAuthorized = authorization.isAuthorized
    }

    func loadState() {
        refreshAuthorization()
        screenTimeManager.rolloverCounterIfNeeded()
        groups = store.screenTimeGroups
        syncProtectionRules()
    }

    func refreshDashboardState() {
        screenTimeManager.reapplyShieldIfOverrideExpired()
        isMonitoring = store.isDailyMonitoringEnabled
        isShieldActive = store.isShieldActive
        oneMinuteRemaining = store.oneMinuteRemaining
        shieldOverrideUntil = store.currentShieldOverrideUntil
        todayStats = store.todayStats
        weeklyStats = store.lastSevenDayStats()
    }

    func handlePickerPresentationChange(isPresented: Bool) {
        if !isPresented {
            pickerGroupID = nil
        }
    }

    func addGroup() {
        guard groups.count < SharedStore.maxGroupCount else {
            alertMessage = GoldTimeAlertMessage(title: "그룹 제한", message: "그룹은 5개까지예요.")
            return
        }
        let group = SharedStore.ScreenTimeGroup(
            name: store.defaultGroupName(for: groups.count)
        )
        groups.append(group)
        persistGroups(shouldSyncProtection: false)
        successMessage = nil
        errorMessage = nil
    }

    func deleteGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
        successMessage = nil
        errorMessage = nil
        persistGroups()
    }

    func updateGroupName(_ id: UUID, name: String) {
        updateGroup(id, shouldSyncProtection: false) { group in
            group.name = name
        }
    }

    func updateGroupLimit(_ id: UUID, minutes: Int) {
        updateGroup(id) { group in
            group.dailyLimitMinutes = minutes
        }
    }

    func presentPicker(for group: SharedStore.ScreenTimeGroup) {
        pickerGroupID = group.id
        pickerSelection = group.selection
        isPickerPresented = true
    }

    func presentLimitPicker(for group: SharedStore.ScreenTimeGroup) {
        limitPickerHours = group.dailyLimitMinutes / 60
        limitPickerMinutes = group.dailyLimitMinutes % 60
        limitPickerGroupID = group.id
    }

    func commitPickerSelection() {
        guard let groupID = pickerGroupID else { return }
        updateGroup(groupID) { group in
            group.selection = pickerSelection.appOnly
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
            try screenTimeManager.resetProtectionState()
            groups = store.screenTimeGroups
            isMonitoring = store.isDailyMonitoringEnabled
            errorMessage = nil
            successMessage = "보호 상태를 초기화하고 유효한 그룹을 다시 적용했어요."
            refreshDashboardState()
        } catch {
            isMonitoring = store.isDailyMonitoringEnabled
            successMessage = nil
            errorMessage = "전체 보호 초기화 실패: \(error.localizedDescription)"
            refreshDashboardState()
        }
    }

    private func persistGroups(shouldSyncProtection: Bool = true) {
        store.screenTimeGroups = groups
        groups = store.screenTimeGroups
        if shouldSyncProtection {
            syncProtectionRules()
        } else {
            isMonitoring = store.isDailyMonitoringEnabled
            refreshDashboardState()
        }
    }

    private func updateGroup(
        _ id: UUID,
        shouldSyncProtection: Bool = true,
        update: (inout SharedStore.ScreenTimeGroup) -> Void
    ) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            return
        }
        update(&groups[index])
        successMessage = nil
        errorMessage = nil
        persistGroups(shouldSyncProtection: shouldSyncProtection)
    }

    private func syncProtectionRules(showSuccess: Bool = false) {
        do {
            try screenTimeManager.syncDailyMonitoring(groups: groups)
            groups = store.screenTimeGroups
            isMonitoring = store.isDailyMonitoringEnabled
            errorMessage = nil
            if showSuccess {
                let count = screenTimeManager.validDailyMonitoringGroups(from: groups).count
                successMessage = count > 0 ? "\(count)개 유효 그룹을 다시 적용했어요." : "적용할 그룹이 없어 보호를 비웠어요."
            }
            refreshDashboardState()
        } catch {
            isMonitoring = store.isDailyMonitoringEnabled
            successMessage = nil
            errorMessage = "자동 적용 실패: \(error.localizedDescription)"
            refreshDashboardState()
        }
    }
}
