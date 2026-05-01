//
//  ScreenTimeManager.swift
//  GoldTime
//
//  DeviceActivityCenter 기반 모니터링 시작/중지, 쉴드 적용/해제, 연장 처리.
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

enum ScreenTimeManager {
    private static var center: DeviceActivityCenter { DeviceActivityCenter() }
    private static var store: ManagedSettingsStore { ManagedSettingsStore(named: .goldtime) }

    // MARK: - 일일 모니터링 시작

    static func startDailyMonitoring(limitMinutes: Int, selection: FamilyActivitySelection) throws {
        SharedStore.dailyLimitMinutes = limitMinutes
        SharedStore.selectedApps = selection
        SharedStore.isShieldActive = false
        SharedStore.shieldOverrideUntil = nil

        // 자정~자정 일일 스케줄
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        // 임계값 도달 이벤트
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: limitMinutes)
        )

        center.stopMonitoring([.daily])
        try center.startMonitoring(.daily, during: schedule, events: [.dailyLimit: event])
    }

    static func stopAllMonitoring() {
        center.stopMonitoring()
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = false
        SharedStore.shieldOverrideUntil = nil
    }

    // MARK: - 쉴드 제어

    static func applyShield() {
        let selection = SharedStore.selectedApps
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        SharedStore.isShieldActive = true
    }

    static func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        SharedStore.isShieldActive = false
    }

    /// 일정 시간 동안 쉴드 해제. 종료 시각에 일회성 DeviceActivitySchedule 콜백으로 재쉴드.
    static func releaseShield(forSeconds seconds: TimeInterval) {
        clearShield()
        let end = Date().addingTimeInterval(seconds)
        SharedStore.shieldOverrideUntil = end

        let calendar = Calendar.current
        let now = Date()
        let startComps = calendar.dateComponents([.hour, .minute, .second], from: now)
        let endComps = calendar.dateComponents([.hour, .minute, .second], from: end)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComps,
            intervalEnd: endComps,
            repeats: false
        )

        center.stopMonitoring([.override])
        try? center.startMonitoring(.override, during: schedule, events: [:])
    }

    // MARK: - 1분 카운터

    /// 카운터를 사용하고 1분 연장. 한도 초과 시 false 반환.
    @discardableResult
    static func consumeOneMinute() -> Bool {
        rolloverCounterIfNeeded()
        guard SharedStore.oneMinuteUsedToday < SharedStore.oneMinuteDailyLimit else {
            return false
        }
        SharedStore.oneMinuteUsedToday += 1
        releaseShield(forSeconds: 60)
        return true
    }

    static func rolloverCounterIfNeeded() {
        let calendar = Calendar.current
        if !calendar.isDateInToday(SharedStore.oneMinuteCounterDate) {
            SharedStore.oneMinuteUsedToday = 0
            SharedStore.oneMinuteCounterDate = Date()
        }
    }
}
