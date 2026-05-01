//
//  SharedStore.swift
//  GoldTime
//
//  App Group UserDefaults 래퍼.
//  메인 앱과 모든 익스텐션(DeviceActivityMonitor / ShieldConfiguration / ShieldAction)이 공유.
//

import Foundation
import FamilyControls

enum SharedStore {
    static let suiteName = "group.com.goldtime.shared"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private enum Key {
        static let selectedApps = "selectedApps"
        static let dailyLimitMinutes = "dailyLimitMinutes"
        static let oneMinuteUsedToday = "oneMinuteUsedToday"
        static let oneMinuteCounterDate = "oneMinuteCounterDate"
        static let isShieldActive = "isShieldActive"
        static let shieldOverrideUntil = "shieldOverrideUntil"
    }

    // MARK: - 차단 대상 앱

    static var selectedApps: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: Key.selectedApps) else {
                return FamilyActivitySelection()
            }
            return (try? JSONDecoder().decode(FamilyActivitySelection.self, from: data))
                ?? FamilyActivitySelection()
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.selectedApps)
        }
    }

    // MARK: - 일일 한도 (분)

    static var dailyLimitMinutes: Int {
        get { defaults.integer(forKey: Key.dailyLimitMinutes) }
        set { defaults.set(newValue, forKey: Key.dailyLimitMinutes) }
    }

    // MARK: - 1분 연장 카운터 (자정 리셋, 0...5)

    static var oneMinuteUsedToday: Int {
        get { defaults.integer(forKey: Key.oneMinuteUsedToday) }
        set { defaults.set(newValue, forKey: Key.oneMinuteUsedToday) }
    }

    static var oneMinuteCounterDate: Date {
        get { defaults.object(forKey: Key.oneMinuteCounterDate) as? Date ?? .distantPast }
        set { defaults.set(newValue, forKey: Key.oneMinuteCounterDate) }
    }

    static let oneMinuteDailyLimit = 5

    static var oneMinuteRemaining: Int {
        max(0, oneMinuteDailyLimit - oneMinuteUsedToday)
    }

    // MARK: - 쉴드 상태

    static var isShieldActive: Bool {
        get { defaults.bool(forKey: Key.isShieldActive) }
        set { defaults.set(newValue, forKey: Key.isShieldActive) }
    }

    static var shieldOverrideUntil: Date? {
        get { defaults.object(forKey: Key.shieldOverrideUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.shieldOverrideUntil) }
    }
}
