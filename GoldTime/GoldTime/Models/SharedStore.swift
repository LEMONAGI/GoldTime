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
        static let isDailyMonitoringEnabled = "isDailyMonitoringEnabled"
        static let oneMinuteUsedToday = "oneMinuteUsedToday"
        static let oneMinuteCounterDate = "oneMinuteCounterDate"
        static let isShieldActive = "isShieldActive"
        static let shieldOverrideUntil = "shieldOverrideUntil"
        static let shieldOpenRequestStartedAt = "shieldOpenRequestStartedAt"
        static let dailyStatsByDate = "dailyStatsByDate"
    }

    static let estimatedWonPerAd = 100

    struct DailyStats: Codable, Equatable, Identifiable {
        var dateKey: String
        var adWatchCount: Int = 0
        var adUnlockedSeconds: Int = 0
        var oneMinuteUsedCount: Int = 0
        var shieldHitCount: Int = 0

        var id: String { dateKey }

        var date: Date {
            SharedStore.date(fromDateKey: dateKey) ?? .distantPast
        }

        var estimatedAdRevenueWon: Int {
            adWatchCount * SharedStore.estimatedWonPerAd
        }

        var totalUnlockedSeconds: Int {
            adUnlockedSeconds + oneMinuteUsedCount * 60
        }
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

    static var isDailyMonitoringEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.isDailyMonitoringEnabled) != nil else {
                return dailyLimitMinutes > 0
            }
            return defaults.bool(forKey: Key.isDailyMonitoringEnabled)
        }
        set { defaults.set(newValue, forKey: Key.isDailyMonitoringEnabled) }
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

    // MARK: - 일별 통계

    static var todayStats: DailyStats {
        stats(for: Date())
    }

    static func stats(for date: Date) -> DailyStats {
        let key = dateKey(for: date)
        return dailyStatsByDate[key] ?? DailyStats(dateKey: key)
    }

    static func lastSevenDayStats(referenceDate: Date = Date()) -> [DailyStats] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: referenceDate)
                ?? referenceDate
            return stats(for: date)
        }
    }

    static func recordAdUnlock(seconds: Int) {
        updateStatsForToday { stats in
            stats.adWatchCount += 1
            stats.adUnlockedSeconds += max(0, seconds)
        }
    }

    static func recordOneMinuteUnlock(seconds: Int) {
        updateStatsForToday { stats in
            if seconds > 0 {
                stats.oneMinuteUsedCount += 1
            }
        }
    }

    static func recordShieldHit() {
        updateStatsForToday { stats in
            stats.shieldHitCount += 1
        }
    }

    #if DEBUG
    static func clearDailyStatsForTesting() {
        defaults.removeObject(forKey: Key.dailyStatsByDate)
    }
    #endif

    // MARK: - 쉴드 상태

    static var isShieldActive: Bool {
        get { defaults.bool(forKey: Key.isShieldActive) }
        set { defaults.set(newValue, forKey: Key.isShieldActive) }
    }

    static var shieldOverrideUntil: Date? {
        get { defaults.object(forKey: Key.shieldOverrideUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.shieldOverrideUntil) }
    }

    static func clearShieldOpenRequest() {
        defaults.removeObject(forKey: Key.shieldOpenRequestStartedAt)
    }

    private static var dailyStatsByDate: [String: DailyStats] {
        get {
            guard let data = defaults.data(forKey: Key.dailyStatsByDate) else {
                return [:]
            }
            return (try? JSONDecoder().decode([String: DailyStats].self, from: data)) ?? [:]
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.dailyStatsByDate)
        }
    }

    private static func updateStatsForToday(_ update: (inout DailyStats) -> Void) {
        let today = Date()
        let key = dateKey(for: today)
        var statsByDate = dailyStatsByDate
        var stats = statsByDate[key] ?? DailyStats(dateKey: key)
        update(&stats)
        statsByDate[key] = stats
        dailyStatsByDate = statsByDate
    }

    static func dateKey(for date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    static func date(fromDateKey dateKey: String) -> Date? {
        dateKeyFormatter.date(from: dateKey)
    }

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
