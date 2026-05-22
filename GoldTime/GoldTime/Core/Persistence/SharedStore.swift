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
        static let overrideDiagnostics = "overrideDiagnostics"
        static let lastRequestedUnlockApplicationToken = "lastRequestedUnlockApplicationToken"
        static let lastRequestedUnlockWebDomainToken = "lastRequestedUnlockWebDomainToken"
        static let shieldOpenRequestStartedAt = "shieldOpenRequestStartedAt"
        static let dailyProtectionStateDate = "dailyProtectionStateDate"
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
            self.selection = selection.supportedTokenSelection
            self.dailyLimitMinutes = dailyLimitMinutes
        }

        var appCount: Int {
            selection.applicationTokens.count
        }

        var webDomainCount: Int {
            selection.webDomainTokens.count
        }

        var selectionCount: Int {
            appCount + webDomainCount
        }

        var hasNonAppTokens: Bool {
            !selection.categoryTokens.isEmpty
        }

        var displayName: String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "이름 없는 그룹" : trimmed
        }
    }

    struct DailyStats: Codable, Equatable, Identifiable {
        var dateKey: String
        var adWatchCount: Int
        var adUnlockedSeconds: Int
        var oneMinuteUsedCount: Int
        var shieldHitCount: Int
        var walkAwayCount: Int

        init(
            dateKey: String,
            adWatchCount: Int = 0,
            adUnlockedSeconds: Int = 0,
            oneMinuteUsedCount: Int = 0,
            shieldHitCount: Int = 0,
            walkAwayCount: Int = 0
        ) {
            self.dateKey = dateKey
            self.adWatchCount = adWatchCount
            self.adUnlockedSeconds = adUnlockedSeconds
            self.oneMinuteUsedCount = oneMinuteUsedCount
            self.shieldHitCount = shieldHitCount
            self.walkAwayCount = walkAwayCount
        }

        private enum CodingKeys: String, CodingKey {
            case dateKey
            case adWatchCount
            case adUnlockedSeconds
            case oneMinuteUsedCount
            case shieldHitCount
            case walkAwayCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dateKey = try container.decode(String.self, forKey: .dateKey)
            adWatchCount = try container.decodeIfPresent(Int.self, forKey: .adWatchCount) ?? 0
            adUnlockedSeconds = try container.decodeIfPresent(Int.self, forKey: .adUnlockedSeconds) ?? 0
            oneMinuteUsedCount = try container.decodeIfPresent(Int.self, forKey: .oneMinuteUsedCount) ?? 0
            shieldHitCount = try container.decodeIfPresent(Int.self, forKey: .shieldHitCount) ?? 0
            walkAwayCount = try container.decodeIfPresent(Int.self, forKey: .walkAwayCount) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(dateKey, forKey: .dateKey)
            try container.encode(adWatchCount, forKey: .adWatchCount)
            try container.encode(adUnlockedSeconds, forKey: .adUnlockedSeconds)
            try container.encode(oneMinuteUsedCount, forKey: .oneMinuteUsedCount)
            try container.encode(shieldHitCount, forKey: .shieldHitCount)
            try container.encode(walkAwayCount, forKey: .walkAwayCount)
        }

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

    struct OverrideDiagnostics: Codable, Equatable {
        var registeredAt: Date?
        var registeredActivityName: String?
        var registeredGroupID: UUID?
        var overrideUntil: Date?
        var registrationMessage: String?
        var intervalDidStartAt: Date?
        var intervalDidStartActivityName: String?
        var intervalWillEndWarningAt: Date?
        var intervalWillEndWarningActivityName: String?
        var intervalWillEndWarningParsedGroupID: UUID?
        var intervalWillEndWarningMessage: String?
        var intervalDidEndAt: Date?
        var intervalDidEndActivityName: String?
        var intervalDidEndParsedGroupID: UUID?
        var intervalDidEndMessage: String?
        var reappliedAt: Date?
        var reappliedTokenCount: Int = 0
        var reappliedMessage: String?
    }

    struct OverrideActivityEndResult: Equatable {
        let parsedGroupID: UUID?
        let didClearOverride: Bool
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
                sanitized.selection = group.selection.supportedTokenSelection
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

    static func previousSevenDayStats(referenceDate: Date = Date()) -> [DailyStats] {
        let anchor = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        return lastSevenDayStats(referenceDate: anchor)
    }

    static func lastNDayStats(_ n: Int, referenceDate: Date = Date()) -> [DailyStats] {
        let calendar = Calendar.current
        let dict = dailyStatsByDate
        return (0..<n).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: referenceDate) ?? referenceDate
            let key = dateKey(for: date)
            return dict[key] ?? DailyStats(dateKey: key)
        }
    }

    static var oldestStatDate: Date? {
        guard let minKey = dailyStatsByDate.keys.min() else { return nil }
        return dateKeyFormatter.date(from: minKey)
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

    static func recordWalkAway() {
        updateStatsForToday { stats in
            stats.walkAwayCount += 1
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
        defaults.removeObject(forKey: Key.overrideDiagnostics)
        defaults.removeObject(forKey: Key.lastRequestedUnlockApplicationToken)
        defaults.removeObject(forKey: Key.lastRequestedUnlockWebDomainToken)
        defaults.removeObject(forKey: Key.isShieldActive)
        defaults.removeObject(forKey: Key.isDailyMonitoringEnabled)
        defaults.removeObject(forKey: Key.oneMinuteUsedToday)
        defaults.removeObject(forKey: Key.oneMinuteCounterDate)
        defaults.removeObject(forKey: Key.dailyProtectionStateDate)
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

    static var overrideDiagnostics: OverrideDiagnostics {
        get {
            guard let data = defaults.data(forKey: Key.overrideDiagnostics),
                  let diagnostics = try? JSONDecoder().decode(OverrideDiagnostics.self, from: data)
            else {
                return OverrideDiagnostics()
            }
            return diagnostics
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.overrideDiagnostics)
        }
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

    static var lastRequestedUnlockWebDomainToken: WebDomainToken? {
        get {
            guard let data = defaults.data(forKey: Key.lastRequestedUnlockWebDomainToken) else {
                return nil
            }
            return try? JSONDecoder().decode(WebDomainToken.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.lastRequestedUnlockWebDomainToken)
                return
            }
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.lastRequestedUnlockWebDomainToken)
        }
    }

    static func clearLastRequestedUnlockTokens() {
        defaults.removeObject(forKey: Key.lastRequestedUnlockApplicationToken)
        defaults.removeObject(forKey: Key.lastRequestedUnlockWebDomainToken)
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

    static func recordOverrideRegistration(
        activityName: String,
        groupID: UUID,
        overrideUntil: Date,
        registeredAt: Date = Date(),
        message: String
    ) {
        var diagnostics = overrideDiagnostics
        diagnostics.registeredAt = registeredAt
        diagnostics.registeredActivityName = activityName
        diagnostics.registeredGroupID = groupID
        diagnostics.overrideUntil = overrideUntil
        diagnostics.registrationMessage = message
        overrideDiagnostics = diagnostics
    }

    static func recordOverrideIntervalDidStart(
        activityName: String,
        startedAt: Date = Date()
    ) {
        var diagnostics = overrideDiagnostics
        diagnostics.intervalDidStartAt = startedAt
        diagnostics.intervalDidStartActivityName = activityName
        overrideDiagnostics = diagnostics
    }

    static func clearOverrideAfterActivityEnd(
        activityName: String,
        now: Date = Date()
    ) -> OverrideActivityEndResult {
        let parsedGroupID = Self.overrideGroupID(fromActivityName: activityName)
        let didClearOverride: Bool
        if let parsedGroupID {
            let overrides = overrideUntilByGroupID
            if let overrideUntil = overrides[parsedGroupID],
               overrideUntil <= now {
                didClearOverride = true
                clearOverride(for: parsedGroupID)
            } else {
                didClearOverride = false
            }
        } else {
            didClearOverride = clearExpiredOverrides(now: now)
        }
        return OverrideActivityEndResult(
            parsedGroupID: parsedGroupID,
            didClearOverride: didClearOverride
        )
    }

    static func recordOverrideIntervalWillEndWarning(
        activityName: String,
        parsedGroupID: UUID?,
        didClearOverride: Bool,
        warnedAt: Date = Date()
    ) {
        var diagnostics = overrideDiagnostics
        diagnostics.intervalWillEndWarningAt = warnedAt
        diagnostics.intervalWillEndWarningActivityName = activityName
        diagnostics.intervalWillEndWarningParsedGroupID = parsedGroupID
        diagnostics.intervalWillEndWarningMessage = didClearOverride
            ? "cleared override from warning"
            : "warning did not clear active override"
        overrideDiagnostics = diagnostics
    }

    static func recordOverrideIntervalDidEnd(
        activityName: String,
        parsedGroupID: UUID?,
        didClearOverride: Bool,
        endedAt: Date = Date()
    ) {
        var diagnostics = overrideDiagnostics
        diagnostics.intervalDidEndAt = endedAt
        diagnostics.intervalDidEndActivityName = activityName
        diagnostics.intervalDidEndParsedGroupID = parsedGroupID
        diagnostics.intervalDidEndMessage = didClearOverride
            ? "cleared override"
            : "no matching override to clear"
        overrideDiagnostics = diagnostics
    }

    static func recordOverrideReapply(
        tokenCount: Int,
        reappliedAt: Date = Date(),
        message: String
    ) {
        var diagnostics = overrideDiagnostics
        diagnostics.reappliedAt = reappliedAt
        diagnostics.reappliedTokenCount = tokenCount
        diagnostics.reappliedMessage = message
        overrideDiagnostics = diagnostics
    }

    static func overrideGroupID(fromActivityName activityName: String) -> UUID? {
        let prefix = "override."
        guard activityName.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(activityName.dropFirst(prefix.count)))
    }

    static func clearAllShieldState() {
        shieldedGroupIDs = []
        overrideUntilByGroupID = [:]
        isShieldActive = false
    }

    @discardableResult
    static func resetDailyProtectionStateIfNeeded(now: Date = Date()) -> Bool {
        let fallbackDate = oneMinuteCounterDate == .distantPast ? nil : oneMinuteCounterDate
        let previousDate = defaults.object(forKey: Key.dailyProtectionStateDate) as? Date
            ?? fallbackDate
        defaults.set(now, forKey: Key.dailyProtectionStateDate)

        guard let previousDate else {
            return false
        }

        guard !Calendar.current.isDate(previousDate, inSameDayAs: now) else {
            return false
        }

        oneMinuteUsedToday = 0
        oneMinuteCounterDate = now
        clearAllShieldState()
        clearLastRequestedUnlockTokens()
        clearShieldOpenRequest()
        return true
    }

    @discardableResult
    static func pruneShieldState(keepingGroupIDs validGroupIDs: Set<UUID>) -> Bool {
        let oldShieldedGroupIDs = shieldedGroupIDs
        let newShieldedGroupIDs = oldShieldedGroupIDs.intersection(validGroupIDs)

        let oldOverrides = overrideUntilByGroupID
        let newOverrides = oldOverrides.filter { validGroupIDs.contains($0.key) }

        let didChange = newShieldedGroupIDs != oldShieldedGroupIDs
            || newOverrides.count != oldOverrides.count

        if didChange {
            shieldedGroupIDs = newShieldedGroupIDs
            overrideUntilByGroupID = newOverrides
        }

        return didChange
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

    static func lockedGroups(containing token: WebDomainToken, now: Date = Date()) -> [ScreenTimeGroup] {
        lockedGroups(now: now).filter { group in
            group.selection.webDomainTokens.contains(token)
        }
    }

    static func shieldApplicationTokens(now: Date = Date()) -> Set<ApplicationToken> {
        lockedGroups(now: now).reduce(into: Set<ApplicationToken>()) { result, group in
            result.formUnion(group.selection.applicationTokens)
        }
    }

    static func shieldWebDomainTokens(now: Date = Date()) -> Set<WebDomainToken> {
        lockedGroups(now: now).reduce(into: Set<WebDomainToken>()) { result, group in
            result.formUnion(group.selection.webDomainTokens)
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
    var supportedTokenSelection: FamilyActivitySelection {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.applicationTokens = applicationTokens
        selection.webDomainTokens = webDomainTokens
        return selection
    }
}
