//
//  GoldTimeApp.swift
//  GoldTime
//

import BackgroundTasks
import SwiftUI

@main
struct GoldTimeApp: App {
    @State private var appLifecycle = AppLifecycleViewModel()
    @State private var contentViewModel = ContentViewModel()
    @State private var settingsViewModel = SettingsViewModel()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Firebase Analytics/Crashlytics 부트스트랩. 모든 Analytics 호출보다 먼저 1회.
        AnalyticsService.shared.configure()

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: MonitoringBackgroundTask.identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MonitoringBackgroundTask.handle(refreshTask)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: contentViewModel,
                settingsViewModel: settingsViewModel,
                showLockOptions: $appLifecycle.showLockOptions
            )
            .sheet(isPresented: $appLifecycle.showLockOptions, onDismiss: {
                appLifecycle.pendingGroupID = nil
            }) {
                LockOptionsView(
                    initialGroupID: appLifecycle.pendingGroupID,
                    entrySource: .shield
                )
            }
            .sheet(isPresented: $contentViewModel.isUnlockSheetPresented) {
                LockOptionsView(
                    initialGroupID: contentViewModel.unlockSheetGroupID,
                    entrySource: .homeGroup
                )
            }
            .sheet(isPresented: $contentViewModel.isAdGatePresented, onDismiss: {
                contentViewModel.handleAdGateDismiss()
            }) {
                RewardedAdView(
                    placement: .groupEditGate,
                    fallbackLabel: contentViewModel.adGateFallbackLabel,
                    onComplete: contentViewModel.adGateCompleted,
                    onCancel: contentViewModel.adGateCancelled
                )
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
                    Task {
                        await appLifecycle.appDidBecomeActive()
                        await contentViewModel.requestScreenTimeAuthorizationOnEntry()
                    }
                }
            }
            .tint(Color.accent)
            .preferredColorScheme(.dark)
        }
    }
}
