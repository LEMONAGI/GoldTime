
//
//  AppLifecycleViewModel.swift
//  GoldTime
//

import Foundation

@MainActor
@Observable
final class AppLifecycleViewModel {
    var showLockOptions = false

    private let authorizeUseCase: AuthorizeUseCase
    private let syncProtectionUseCase: SyncProtectionUseCase
    private let shieldRepository: any ShieldRepository
    private let notificationRepository: any NotificationRepository

    init(
        authorizeUseCase: AuthorizeUseCase? = nil,
        syncProtectionUseCase: SyncProtectionUseCase? = nil,
        shieldRepository: (any ShieldRepository)? = nil,
        notificationRepository: (any NotificationRepository)? = nil
    ) {
        let resolvedShield = shieldRepository ?? ShieldRepositoryImpl()
        let resolvedNotification = notificationRepository ?? NotificationRepositoryImpl()
        self.shieldRepository = resolvedShield
        self.notificationRepository = resolvedNotification
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
        MonitoringBackgroundTask.scheduleNext()
        notificationRepository.scheduleWeeklyStatsNotification(weekStartDay: SharedStore.weekStartDay)
    }

    func refreshLockOptionsPresentation() {
        syncProtectionUseCase.prepareForAppActivation()
        if shieldRepository.hasPendingShieldOpenRequest() {
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
