//
//  GoldTimeApp.swift
//  GoldTime
//

import BackgroundTasks
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
            .sheet(isPresented: $appLifecycle.showLockOptions) {
                LockOptionsView()
            }
            .sheet(isPresented: $contentViewModel.isUnlockSheetPresented) {
                LockOptionsView(initialGroupID: contentViewModel.unlockSheetGroupID)
            }
            .confirmationDialog(
                "잠긴 그룹",
                isPresented: $contentViewModel.isAdGateConfirmPresented
            ) {
                Button(contentViewModel.adGateConfirmButtonLabel) {
                    contentViewModel.confirmAdGate()
                }
                Button("취소", role: .cancel) {
                    contentViewModel.cancelAdGateConfirm()
                }
            } message: {
                Text("잠겨있는 그룹은 광고를 통해 제한 항목 편집 또는 삭제할 수 있어요.")
            }
            .sheet(isPresented: $contentViewModel.isAdGatePresented) {
                RewardedAdView(
                    fallbackLabel: contentViewModel.adGateFallbackLabel,
                    onComplete: contentViewModel.adGateCompleted,
                    onCancel: contentViewModel.adGateCancelled
                )
            }
            .confirmationDialog(
                "그룹 삭제",
                isPresented: Binding(
                    get: { contentViewModel.deleteConfirmGroupID != nil },
                    set: { if !$0 { contentViewModel.deleteConfirmGroupID = nil } }
                )
            ) {
                Button("삭제", role: .destructive) {
                    contentViewModel.confirmDelete()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("그룹을 삭제하면 되돌릴 수 없어요.")
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
            .preferredColorScheme(.dark)
        }
    }
}
