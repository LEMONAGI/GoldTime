//
//  GoldTimeApp.swift
//  GoldTime
//

import SwiftData
import SwiftUI

@main
struct GoldTimeApp: App {
    @State private var showLockOptions = false

    init() {
        RewardedAdService.configure()
        RewardedAdService.shared.loadAd()
    }
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(showLockOptions: $showLockOptions)
                .sheet(isPresented: $showLockOptions) {
                    LockOptionsView()
                }
                .onAppear {
                    syncProtectionRulesIfAuthorized()
                    refreshLockOptionsPresentation()
                }
                .onOpenURL { _ in
                    refreshLockOptionsPresentation()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        AuthorizationService.shared.refresh()
                        syncProtectionRulesIfAuthorized()
                        refreshLockOptionsPresentation()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func refreshLockOptionsPresentation() {
        ScreenTimeManager.rolloverCounterIfNeeded()
        ScreenTimeManager.reapplyShieldIfOverrideExpired()

        let shouldPresentLockOptions =
            SharedStore.hasPendingShieldOpenRequest()
            || SharedStore.isShieldActive
            || !SharedStore.lockedGroups().isEmpty

        if shouldPresentLockOptions {
            showLockOptions = true
        }
    }

    private func syncProtectionRulesIfAuthorized() {
        guard AuthorizationService.shared.isAuthorized else {
            return
        }

        do {
            try ScreenTimeManager.syncDailyMonitoring(groups: SharedStore.screenTimeGroups)
        } catch {
            print("Failed to sync protection rules: \(error.localizedDescription)")
        }
    }
}
