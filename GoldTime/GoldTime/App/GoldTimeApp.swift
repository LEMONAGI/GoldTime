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

    @Environment(\.scenePhase) private var scenePhase

    init() {
        RewardedAdService.configure()
        RewardedAdService.shared.loadAd()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: contentViewModel, showLockOptions: $appLifecycle.showLockOptions)
                .sheet(isPresented: $appLifecycle.showLockOptions) {
                    LockOptionsView()
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
        }
    }
}
