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
            HomeView(showLockOptions: $showLockOptions)
                .sheet(isPresented: $showLockOptions) {
                    LockOptionsView()
                }
                .onAppear {
                    ScreenTimeManager.rolloverCounterIfNeeded()
                    ScreenTimeManager.reapplyShieldIfOverrideExpired()
                    SharedStore.clearShieldOpenRequest()
                    showLockOptions = SharedStore.isShieldActive
                }
                .onOpenURL { _ in
                    ScreenTimeManager.reapplyShieldIfOverrideExpired()
                    SharedStore.clearShieldOpenRequest()
                    showLockOptions = SharedStore.isShieldActive
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        AuthorizationService.shared.refresh()
                        ScreenTimeManager.reapplyShieldIfOverrideExpired()
                        SharedStore.clearShieldOpenRequest()
                        showLockOptions = SharedStore.isShieldActive
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
