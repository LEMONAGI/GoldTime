//
//  GoldTimeApp.swift
//  GoldTime
//

import SwiftData
import SwiftUI

@main
struct GoldTimeApp: App {
    @State private var appLifecycle = AppLifecycleViewModel()
    @State private var contentViewModel = ContentViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        RewardedAdService.configure()
        RewardedAdService.shared.loadAd()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: contentViewModel,
                settingsViewModel: settingsViewModel,
                showLockOptions: $appLifecycle.showLockOptions
            )
            .sheet(isPresented: $appLifecycle.showLockOptions) {
                LockOptionsView()
            }
            .sheet(isPresented: $contentViewModel.isUnlockSheetPresented) {
                LockOptionsView(initialGroupID: contentViewModel.unlockSheetGroupID)
            }
            .onChange(of: contentViewModel.isUnlockSheetPresented) { _, newValue in
                if !newValue {
                    contentViewModel.unlockSheetGroupID = nil
                    contentViewModel.refreshDashboardState()
                }
            }
            .onAppear {
                appLifecycle.appDidAppear()
            }
            .onOpenURL { _ in
                appLifecycle.appDidOpenURL()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    appLifecycle.appDidBecomeActive()
                }
            }
            .tint(Color.accent)
        }
    }
}
