//
//  GoldTimeApp.swift
//  GoldTime
//

import SwiftData
import SwiftUI

@main
struct GoldTimeApp: App {
    @State private var showLockOptions = false

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
                    showLockOptions = SharedStore.isShieldActive
                }
                .onOpenURL { _ in
                    showLockOptions = SharedStore.isShieldActive
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
