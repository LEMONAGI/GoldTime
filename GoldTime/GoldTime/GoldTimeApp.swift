//
//  GoldTimeApp.swift
//  GoldTime
//

import SwiftData
import SwiftUI

@main
struct GoldTimeApp: App {
    @State private var showLockOptions = false
    @Environment(\.scenePhase) private var scenePhase

    private func reapplyShieldIfOverrideExpired() {
        if let until = SharedStore.shieldOverrideUntil, until <= Date() {
            ScreenTimeManager.applyShield()
            SharedStore.shieldOverrideUntil = nil
        }
    }

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
                    reapplyShieldIfOverrideExpired()
                    showLockOptions = SharedStore.isShieldActive
                }
                .onOpenURL { _ in
                    reapplyShieldIfOverrideExpired()
                    showLockOptions = SharedStore.isShieldActive
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        AuthorizationService.shared.refresh()
                        reapplyShieldIfOverrideExpired()
                        showLockOptions = SharedStore.isShieldActive
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
