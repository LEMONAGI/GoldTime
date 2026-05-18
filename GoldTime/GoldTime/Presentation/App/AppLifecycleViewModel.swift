//
//  AppLifecycleViewModel.swift
//  GoldTime
//

import Foundation

@MainActor
@Observable
final class AppLifecycleViewModel {
    var showLockOptions = false

    private var store: any GoldTimeStoreProviding
    private let screenTimeManager: any ScreenTimeManaging
    private let authorization: any AuthorizationProviding

    init(
        store: (any GoldTimeStoreProviding)? = nil,
        screenTimeManager: (any ScreenTimeManaging)? = nil,
        authorization: (any AuthorizationProviding)? = nil
    ) {
        self.store = store ?? GoldTimeStoreAdapter()
        self.screenTimeManager = screenTimeManager ?? ScreenTimeManagerAdapter()
        self.authorization = authorization ?? AuthorizationService.shared
    }

    func appDidAppear() {
        syncProtectionRulesIfAuthorized()
        refreshLockOptionsPresentation()
    }

    func appDidOpenURL() {
        refreshLockOptionsPresentation()
    }

    func appDidBecomeActive() {
        authorization.refresh()
        syncProtectionRulesIfAuthorized()
        refreshLockOptionsPresentation()
    }

    func refreshLockOptionsPresentation() {
        screenTimeManager.rolloverCounterIfNeeded()
        screenTimeManager.reapplyShieldIfOverrideExpired()

        let shouldPresentLockOptions =
            store.hasPendingShieldOpenRequest()
            || store.isShieldActive
            || !store.lockedGroups().isEmpty

        if shouldPresentLockOptions {
            showLockOptions = true
        }
    }

    private func syncProtectionRulesIfAuthorized() {
        guard authorization.isAuthorized else {
            return
        }

        do {
            try screenTimeManager.syncDailyMonitoring(groups: store.screenTimeGroups)
        } catch {
            print("Failed to sync protection rules: \(error.localizedDescription)")
        }
    }
}
