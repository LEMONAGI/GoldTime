//
//  SharedStore.swift
//  GoldTime
//
//  App Group UserDefaults 래퍼.
//  메인 앱과 모든 익스텐션(DeviceActivityMonitor / ShieldConfiguration / ShieldAction)이 공유.
//

import Foundation
import FamilyControls
import ManagedSettings

enum SharedStore {
    static let suiteName = "group.com.goldtime.shared"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private enum Key {
        static let screenTimeGroups = "screenTimeGroups"
        static let isDailyMonitoringEnabled = "isDailyMonitoringEnabled"
        static let oneMinuteUsedToday = "oneMinuteUsedToday"
        static let oneMinuteCounterDate = "oneMinuteCounterDate"
        static let isShieldActive = "isShieldActive"
        static let shieldedGroupIDs = "shieldedGroupIDs"
        static let overrideUntilByGroupID = "overrideUntilByGroupID"
        static let lastRequestedUnlockApplicationToken = "lastRequestedUnlockApplicationToken"
        static let shieldOpenRequestStartedAt = "shieldOpenRequestStartedAt"
        static let dailyStatsByDate = "dailyStatsByDate"
    }

    static let estimatedWonPerAd = 100
    static let maxGroupCount = 5
    static let maxAppsPerGroup = 9
    static let maxShieldApplicationCount = 49

    struct ScreenTimeGroup: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var selection: FamilyActivitySelection
        var dailyLimitMinutes: Int

        init(
            id: UUID = UUID(),
            name: String,
            selection: FamilyActivitySelection = FamilyActivitySelection(),
            dailyLimitMinutes: Int = 30
        ) {
            self.id = id
            self.name = name
            self.selection = selection.appOnly
            self.dailyLimitMinutes = dailyLimitMinutes
        }

        var appCount: Int {
            selection.applicationTokens.count
        }

        var hasNonAppTokens: Bool {
            !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
        }

        var displayName: String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "이름 없는 그룹" : trimmed
        }
    }

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

    // MARK: - 그룹 설정

    static var screenTimeGroups: [ScreenTimeGroup] {
        get {
            guard let data = defaults.data(forKey: Key.screenTimeGroups) else {
                return []
            }
            return (try? JSONDecoder().decode([ScreenTimeGroup].self, from: data)) ?? []
        }
        set {
            let groups = Array(newValue.prefix(maxGroupCount)).map { group in
                var sanitized = group
                sanitized.selection = group.selection.appOnly
                return sanitized
            }
            let data = try? JSONEncoder().encode(groups)
            defaults.set(data, forKey: Key.screenTimeGroups)
        }
    }

    static func defaultGroupName(for index: Int) -> String {
        "그룹 \(index + 1)"
    }

    static func group(id: UUID) -> ScreenTimeGroup? {
        screenTimeGroups.first { $0.id == id }
    }

    static var isDailyMonitoringEnabled: Bool {
        get { defaults.bool(forKey: Key.isDailyMonitoringEnabled) }
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

    static func clearGroupStateForTesting() {
        defaults.removeObject(forKey: Key.screenTimeGroups)
        defaults.removeObject(forKey: Key.shieldedGroupIDs)
        defaults.removeObject(forKey: Key.overrideUntilByGroupID)
        defaults.removeObject(forKey: Key.lastRequestedUnlockApplicationToken)
        defaults.removeObject(forKey: Key.isShieldActive)
        defaults.removeObject(forKey: Key.isDailyMonitoringEnabled)
        defaults.removeObject(forKey: Key.oneMinuteUsedToday)
        defaults.removeObject(forKey: Key.oneMinuteCounterDate)
    }
    #endif

    // MARK: - 쉴드 상태

    static var isShieldActive: Bool {
        get { defaults.bool(forKey: Key.isShieldActive) }
        set { defaults.set(newValue, forKey: Key.isShieldActive) }
    }

    static var shieldedGroupIDs: Set<UUID> {
        get {
            guard let data = defaults.data(forKey: Key.shieldedGroupIDs) else {
                return []
            }
            let strings = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            return Set(strings.compactMap(UUID.init(uuidString:)))
        }
        set {
            let data = try? JSONEncoder().encode(newValue.map(\.uuidString))
            defaults.set(data, forKey: Key.shieldedGroupIDs)
        }
    }

    static var overrideUntilByGroupID: [UUID: Date] {
        get {
            guard let data = defaults.data(forKey: Key.overrideUntilByGroupID) else {
                return [:]
            }
            let raw = (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
            return Dictionary(
                uniqueKeysWithValues: raw.compactMap { key, value in
                    guard let id = UUID(uuidString: key) else { return nil }
                    return (id, value)
                }
            )
        }
        set {
            let raw = Dictionary(
                uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) }
            )
            let data = try? JSONEncoder().encode(raw)
            defaults.set(data, forKey: Key.overrideUntilByGroupID)
        }
    }

    static var currentShieldOverrideUntil: Date? {
        let now = Date()
        return overrideUntilByGroupID.values
            .filter { $0 > now }
            .max()
    }

    static var lastRequestedUnlockApplicationToken: ApplicationToken? {
        get {
            guard let data = defaults.data(forKey: Key.lastRequestedUnlockApplicationToken) else {
                return nil
            }
            return try? JSONDecoder().decode(ApplicationToken.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.lastRequestedUnlockApplicationToken)
                return
            }
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.lastRequestedUnlockApplicationToken)
        }
    }

    static func clearLastRequestedUnlockApplicationToken() {
        defaults.removeObject(forKey: Key.lastRequestedUnlockApplicationToken)
    }

    static func setOverride(until date: Date, for groupID: UUID) {
        var overrides = overrideUntilByGroupID
        overrides[groupID] = date
        overrideUntilByGroupID = overrides
    }

    static func clearOverride(for groupID: UUID) {
        var overrides = overrideUntilByGroupID
        overrides.removeValue(forKey: groupID)
        overrideUntilByGroupID = overrides
    }

    static func clearAllShieldState() {
        shieldedGroupIDs = []
        overrideUntilByGroupID = [:]
        isShieldActive = false
    }

    static func markGroupShielded(_ groupID: UUID) {
        var ids = shieldedGroupIDs
        ids.insert(groupID)
        shieldedGroupIDs = ids
    }

    @discardableResult
    static func clearExpiredOverrides(now: Date = Date()) -> Bool {
        let overrides = overrideUntilByGroupID
        let activeOverrides = overrides.filter { $0.value > now }
        guard activeOverrides.count != overrides.count else {
            return false
        }
        overrideUntilByGroupID = activeOverrides
        return true
    }

    static func groupsInOverride(now: Date = Date()) -> [ScreenTimeGroup] {
        clearExpiredOverrides(now: now)
        let overrides = overrideUntilByGroupID
        return screenTimeGroups.filter { group in
            if let until = overrides[group.id] {
                return until > now
            }
            return false
        }
    }

    static func lockedGroups(now: Date = Date()) -> [ScreenTimeGroup] {
        clearExpiredOverrides(now: now)
        let ids = shieldedGroupIDs
        let overrides = overrideUntilByGroupID
        return screenTimeGroups.filter { group in
            ids.contains(group.id) && (overrides[group.id] ?? .distantPast) <= now
        }
    }

    static func lockedGroups(containing token: ApplicationToken, now: Date = Date()) -> [ScreenTimeGroup] {
        lockedGroups(now: now).filter { group in
            group.selection.applicationTokens.contains(token)
        }
    }

    static func shieldApplicationTokens(now: Date = Date()) -> Set<ApplicationToken> {
        lockedGroups(now: now).reduce(into: Set<ApplicationToken>()) { result, group in
            result.formUnion(group.selection.applicationTokens)
        }
    }

    static func hasPendingShieldOpenRequest(
        now: Date = Date(),
        pendingWindow: TimeInterval = 30
    ) -> Bool {
        guard let startedAt = defaults.object(forKey: Key.shieldOpenRequestStartedAt) as? Date else {
            return false
        }
        return now.timeIntervalSince(startedAt) <= pendingWindow
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

extension FamilyActivitySelection {
    var appOnly: FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = applicationTokens
        return selection
    }
}
