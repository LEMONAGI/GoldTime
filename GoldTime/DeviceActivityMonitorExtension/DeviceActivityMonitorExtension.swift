//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

extension DeviceActivityName {
    static let daily = Self("daily")
    static let override = Self("override")
}

extension DeviceActivityEvent.Name {
    static let dailyLimit = Self("dailyLimit")
}

extension ManagedSettingsStore.Name {
    static let goldtime = Self("goldtime")
}

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private var store: ManagedSettingsStore { ManagedSettingsStore(named: .goldtime) }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == .daily {
            SharedStore.oneMinuteUsedToday = 0
            SharedStore.oneMinuteCounterDate = Date()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isShieldActive = false
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        switch activity {
        case .daily:
            SharedStore.oneMinuteUsedToday = 0
            SharedStore.oneMinuteCounterDate = Date()
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            SharedStore.isShieldActive = false
        case .override:
            applyShieldFromSelection()
            SharedStore.shieldOverrideUntil = nil
        default:
            break
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        if event == .dailyLimit {
            applyShieldFromSelection()
        }
    }

    private func applyShieldFromSelection() {
        let selection = SharedStore.selectedApps
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil : selection.webDomainTokens
        SharedStore.isShieldActive = true
    }
}
