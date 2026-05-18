
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

    init(
        authorizeUseCase: AuthorizeUseCase? = nil,
        syncProtectionUseCase: SyncProtectionUseCase? = nil,
        shieldRepository: (any ShieldRepository)? = nil
    ) {
        let resolvedShield = shieldRepository ?? ShieldRepositoryImpl()
        self.shieldRepository = resolvedShield
        self.authorizeUseCase = authorizeUseCase ?? AuthorizeUseCase(
            authRepository: AuthorizationRepositoryImpl(),
            notificationRepository: NotificationRepositoryImpl()
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
    }

    func refreshLockOptionsPresentation() {
        syncProtectionUseCase.prepareForAppActivation()
        let shouldPresentLockOptions =
            shieldRepository.hasPendingShieldOpenRequest()
            || shieldRepository.isShieldActive
            || !shieldRepository.lockedGroups().isEmpty

        if shouldPresentLockOptions {
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
