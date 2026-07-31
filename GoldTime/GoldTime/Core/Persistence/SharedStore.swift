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
        static let cooldownUntilByGroupID = "cooldownUntilByGroupID"
        static let cooldownGenerationByID = "cooldownGenerationByID"
        static let overrideDiagnostics = "overrideDiagnostics"
        static let lastRequestedUnlockApplicationToken = "lastRequestedUnlockApplicationToken"
        static let lastRequestedUnlockWebDomainToken = "lastRequestedUnlockWebDomainToken"
        static let shieldOpenRequestStartedAt = "shieldOpenRequestStartedAt"
        static let dailyProtectionStateDate = "dailyProtectionStateDate"
        static let dailyStatsByDate = "dailyStatsByDate"
        static let weekStartDay = "weekStartDay"
        static let usedTimeByGroupID = "usedTimeByGroupID"
        static let dailyBaselineByGroupID = "dailyBaselineByGroupID"
        static let cooldownBaselineByGroupID = "cooldownBaselineByGroupID"
        static let lastRegisteredGroupsByID = "lastRegisteredGroupsByID"
        static let lastRegisteredGenerationByID = "lastRegisteredGenerationByID"
        static let usageBasedOverrideGroupIDs = "usageBasedOverrideGroupIDs"
        static let overrideBaselineUsedTimeByGroupID = "overrideBaselineUsedTimeByGroupID"
        static let overrideGrantedMinutesByGroupID = "overrideGrantedMinutesByGroupID"
        static let lastMorningNotificationDate = "lastMorningNotificationDate"
        static let isDailyMorningNotificationEnabled = "isDailyMorningNotificationEnabled"
        static let isUsageAlertEnabled = "isUsageAlertEnabled"
        static let usageAlertSentByGroupID = "usageAlertSentByGroupID"
        static let overrideAlertSentByGroupID = "overrideAlertSentByGroupID"
        static let statsTrackingStartDate = "statsTrackingStartDate"
        static let pendingAnalyticsEvents = "pendingAnalyticsEvents"
        static let isStrictLockEnabled = "isStrictLockEnabled"
    }

    /// 연장 불가 모드(기간 강력 잠금) 기능 사용 여부. **기본값 Off** — 한 번 걸면 어떤 수단으로도
    /// 못 푸는 기능이라 원하는 사용자만 명시적으로 켠다(설정 → 연장 불가 모드 토글).
    /// Off면 그룹 카드에 연장 불가 행이 보이지 않고 켜기 진입도 막힌다. **연장 불가 기간 중인 그룹이 있으면
    /// 끌 수 없다**(끄기로 우회 해제하는 구멍 차단 — `ManageGroupsUseCase.setStrictLockEnabled`).
    static var isStrictLockEnabled: Bool {
        get { defaults.bool(forKey: Key.isStrictLockEnabled) }
        set { defaults.set(newValue, forKey: Key.isStrictLockEnabled) }
    }

    /// 하루 요약(오전 9시) 알림 수신 여부. 기본값 On.
    /// 앱 복귀 알림(쉴드 진입용)은 별도 토글 없이 항상 발송된다.
    static var isDailyMorningNotificationEnabled: Bool {
        get {
            if defaults.object(forKey: Key.isDailyMorningNotificationEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Key.isDailyMorningNotificationEnabled)
        }
        set { defaults.set(newValue, forKey: Key.isDailyMorningNotificationEnabled) }
    }

    /// 사용·차단 알림(한도 50·90% 임박, 시간대 차단 5분 전, 쿨다운·시간대 재사용 가능) 수신 여부.
    /// 기본값 On. 한도 도달 시 쉴드 진입 유도 알림(`scheduleOpenAppNotification`)과는 별개다.
    static var isUsageAlertEnabled: Bool {
        get {
            if defaults.object(forKey: Key.isUsageAlertEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Key.isUsageAlertEnabled)
        }
        set { defaults.set(newValue, forKey: Key.isUsageAlertEnabled) }
    }

    /// 일일/쿨다운 사이클에서 이미 발송한 사용량 알림 단계(percent) 집합. 중복 발송을 막는다.
    /// 자정 리셋(`clearAllShieldState`)·쿨다운 재충전(`endCooldownAndRecharge`)·규칙 전환
    /// (`clearCooldownCycle`)에서 해당 그룹을 비운다. ⚠️ 디코딩은 절대 throw하지 않는다(빈 dict fallback).
    static var usageAlertSentByGroupID: [UUID: Set<Int>] {
        get {
            guard let data = defaults.data(forKey: Key.usageAlertSentByGroupID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: [Int]].self, from: data)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, Set(value)) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, Array($0.value)) })
            let data = try? JSONEncoder().encode(raw)
            defaults.set(data, forKey: Key.usageAlertSentByGroupID)
        }
    }

    /// 연장(광고/1분) 측정창에서 이미 발송한 사용량 알림 단계(percent) 집합. 연장 생애 동안만 유효하며
    /// 연장 시작(`recordOverrideBaseline`)·종료(`clearOverride`/`clearAllOverrideState`)에서 비운다.
    static var overrideAlertSentByGroupID: [UUID: Set<Int>] {
        get {
            guard let data = defaults.data(forKey: Key.overrideAlertSentByGroupID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: [Int]].self, from: data)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, Set(value)) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, Array($0.value)) })
            let data = try? JSONEncoder().encode(raw)
            defaults.set(data, forKey: Key.overrideAlertSentByGroupID)
        }
    }

    /// 사이클(일일/쿨다운)에서 percent 단계 알림을 아직 안 보냈으면 true + 발송 기록(compare-and-set).
    /// 같은 tick이 중복 도착해도 한 번만 통과한다.
    static func claimUsageAlert(percent: Int, for groupID: UUID) -> Bool {
        var map = usageAlertSentByGroupID
        var sent = map[groupID] ?? []
        guard sent.insert(percent).inserted else { return false }
        map[groupID] = sent
        usageAlertSentByGroupID = map
        return true
    }

    static func clearUsageAlerts(for groupID: UUID) {
        var map = usageAlertSentByGroupID
        guard map.removeValue(forKey: groupID) != nil else { return }
        usageAlertSentByGroupID = map
    }

    /// 연장 측정창에서 percent 단계 알림 발송 여부(compare-and-set). `claimUsageAlert`의 override 버전.
    static func claimOverrideAlert(percent: Int, for groupID: UUID) -> Bool {
        var map = overrideAlertSentByGroupID
        var sent = map[groupID] ?? []
        guard sent.insert(percent).inserted else { return false }
        map[groupID] = sent
        overrideAlertSentByGroupID = map
        return true
    }

    static func clearOverrideAlerts(for groupID: UUID) {
        var map = overrideAlertSentByGroupID
        guard map.removeValue(forKey: groupID) != nil else { return }
        overrideAlertSentByGroupID = map
    }

    /// 아침 사용량 알림을 오늘 아직 예약하지 않았다면 true를 반환하고 오늘 날짜를 기록한다.
    /// 자정 `intervalDidStart`가 그룹 수만큼 중복 호출되고 BGTask 폴백까지 겹쳐도
    /// 하루 한 번만 실제 예약이 일어나도록 막는 compare-and-set 가드.
    @discardableResult
    static func claimMorningNotificationSlot(now: Date = Date()) -> Bool {
        let todayKey = dateKey(for: now)
        if defaults.string(forKey: Key.lastMorningNotificationDate) == todayKey {
            return false
        }
        defaults.set(todayKey, forKey: Key.lastMorningNotificationDate)
        return true
    }

    /// 테스트/디버그용: 아침 알림 예약 가드를 초기화한다.
    static func resetMorningNotificationSlot() {
        defaults.removeObject(forKey: Key.lastMorningNotificationDate)
    }

    // 1 = 일요일, 2 = 월요일 (Calendar.firstWeekday 기준), 기본값: 2 (월요일)
    static var weekStartDay: Int {
        get {
            let v = defaults.integer(forKey: Key.weekStartDay)
            return v == 0 ? 2 : v
        }
        set { defaults.set(newValue, forKey: Key.weekStartDay) }
    }

    static let estimatedWonPerAd = 100
    static let maxGroupCount = 5
    static let maxAppsPerGroup = 9
    static let maxShieldApplicationCount = 49

    /// 하루 안의 차단 시간대. 분 단위(0...1439), start·end 모두 포함(inclusive: end가 차단되는
    /// 마지막 분), 자정 넘김 금지(start <= end). 예: 12:00–12:59는 12:00:00~12:59:59 차단.
    /// DeviceActivitySchedule 등록 시에는 intervalEnd = endMinuteOfDay + 1로 변환한다
    /// (TimeWindowMonitor.startWindowMonitoring 참조).
    struct TimeWindow: Codable, Equatable, Hashable, Identifiable {
        var id: UUID
        var startMinuteOfDay: Int
        var endMinuteOfDay: Int

        init(id: UUID = UUID(), startMinuteOfDay: Int, endMinuteOfDay: Int) {
            self.id = id
            self.startMinuteOfDay = startMinuteOfDay
            self.endMinuteOfDay = endMinuteOfDay
        }

        var durationMinutes: Int {
            endMinuteOfDay - startMinuteOfDay + 1
        }

        func contains(minuteOfDay minute: Int) -> Bool {
            minute >= startMinuteOfDay && minute <= endMinuteOfDay
        }
    }

    /// 요일 하나의 완전한 규칙. ScreenTimeGroup의 규칙 필드와 동일한 평면 구조로,
    /// 규칙 종류를 전환해도 다른 종류의 설정값이 보존된다(그룹 레벨과 동일한 패턴).
    /// Hashable은 요일 묶음 편집의 value 기반 내비게이션(NavigationLink(value:))용.
    struct DayRule: Codable, Equatable, Hashable {
        /// 요일 규칙 종류. 그룹 RuleKind와 달리 '제한 없음(unrestricted)'이 있다.
        enum Kind: String, Codable {
            case unrestricted
            case dailyLimit
            case timeWindows
            case cooldown
        }

        var kind: Kind
        var dailyLimitMinutes: Int
        var timeWindows: [TimeWindow]
        var cooldownUsageMinutes: Int
        var cooldownDurationMinutes: Int
        /// 표시 전용 — 편집 화면에서 직접 '제한 없음'을 골라 저장한 요일. 엔진/정책/투영은 kind만 본다.
        /// (토글 시드·묶음 해제로 생긴 암묵적 '제한 없음'과 구분해 요일 묶음 행을 만들지 결정한다.)
        var isExplicitlyUnrestricted: Bool

        init(
            kind: Kind,
            dailyLimitMinutes: Int = 30,
            timeWindows: [TimeWindow] = [],
            cooldownUsageMinutes: Int = ScreenTimeGroup.defaultCooldownUsageMinutes,
            cooldownDurationMinutes: Int = ScreenTimeGroup.defaultCooldownDurationMinutes,
            isExplicitlyUnrestricted: Bool = false
        ) {
            self.kind = kind
            self.dailyLimitMinutes = dailyLimitMinutes
            self.timeWindows = timeWindows
            self.cooldownUsageMinutes = cooldownUsageMinutes
            self.cooldownDurationMinutes = cooldownDurationMinutes
            // 불변식: 제한 kind에 flag가 섞이면 같은 파라미터 묶음이 두 행으로 쪼개진다 → unrestricted에서만 유효.
            self.isExplicitlyUnrestricted = isExplicitlyUnrestricted && kind == .unrestricted
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case dailyLimitMinutes
            case timeWindows
            case cooldownUsageMinutes
            case cooldownDurationMinutes
            case isExplicitlyUnrestricted
        }

        // 배열 요소 1개의 디코딩 실패가 배열 전체 소실로 이어지지 않도록 어떤 페이로드에서도 throw하지 않는다.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let rawKind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil {
                // 미래 버전의 미지 kind 값(및 키 부재)에서도 보호가 끊기지 않도록 일일 한도로 fallback.
                kind = Kind(rawValue: rawKind) ?? .dailyLimit
            } else {
                kind = .dailyLimit
            }
            dailyLimitMinutes = (try? container.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)) ?? nil ?? 30
            timeWindows = (try? container.decodeIfPresent([TimeWindow].self, forKey: .timeWindows)) ?? nil ?? []
            cooldownUsageMinutes = (try? container.decodeIfPresent(Int.self, forKey: .cooldownUsageMinutes)) ?? nil ?? ScreenTimeGroup.defaultCooldownUsageMinutes
            cooldownDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .cooldownDurationMinutes)) ?? nil ?? ScreenTimeGroup.defaultCooldownDurationMinutes
            // 표시 전용 플래그. 키 부재·손상 시 false, init과 동일하게 unrestricted에서만 유효하도록 정규화한다.
            let explicitFlag = ((try? container.decodeIfPresent(Bool.self, forKey: .isExplicitlyUnrestricted)) ?? nil) ?? false
            isExplicitlyUnrestricted = explicitFlag && kind == .unrestricted
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(dailyLimitMinutes, forKey: .dailyLimitMinutes)
            try container.encode(timeWindows, forKey: .timeWindows)
            try container.encode(cooldownUsageMinutes, forKey: .cooldownUsageMinutes)
            try container.encode(cooldownDurationMinutes, forKey: .cooldownDurationMinutes)
            // true일 때만 인코딩 — implicit·제한 요일 페이로드는 기존과 바이트 동일(하위 호환).
            if isExplicitlyUnrestricted {
                try container.encode(isExplicitlyUnrestricted, forKey: .isExplicitlyUnrestricted)
            }
        }
    }

    struct ScreenTimeGroup: Codable, Equatable, Identifiable {
        /// 그룹 잠금 규칙 종류. nil이면 아직 규칙을 고르지 않은 설정 중(draft) 상태.
        enum RuleKind: String, Codable {
            case dailyLimit
            case timeWindows
            case cooldown
        }

        /// 쿨다운 모드 기본 상수. custom Codable 부재 시 기본값과 반드시 동일해야 한다.
        static let defaultCooldownUsageMinutes: Int = 10
        static let defaultCooldownDurationMinutes: Int = 300

        var id: UUID
        var name: String
        var selection: FamilyActivitySelection
        var dailyLimitMinutes: Int
        var ruleKind: RuleKind?
        var timeWindows: [TimeWindow]
        var isApplied: Bool
        /// 쿨다운 모드: 사용 예산(분). ruleKind == .cooldown 일 때 유효.
        var cooldownUsageMinutes: Int
        /// 쿨다운 모드: 강제 휴식(분). ruleKind == .cooldown 일 때 유효.
        var cooldownDurationMinutes: Int
        /// 요일별 규칙. index = Calendar.component(.weekday) - 1 (0=일 … 6=토), 정확히 7개.
        /// nil이면 요일별 모드가 아니며 기존 필드(ruleKind 등)가 매일 적용된다.
        var weekdayRules: [DayRule]?
        /// 연장 불가 기간 만료 시각(자정 경계). nil = 연장 불가 기간 없음/미적용. 만료 판정은 항상 lazy
        /// (저장값 청소 이벤트 없음)라 만료 후에도 과거 날짜로 남는다 — `isStrictLockActive` 참조.
        var strictUntil: Date?
        /// 연장 불가 기간 시작 시각(표시용). nil 허용.
        var strictStartedAt: Date?

        init(
            id: UUID = UUID(),
            name: String,
            selection: FamilyActivitySelection = FamilyActivitySelection(),
            dailyLimitMinutes: Int = 30,
            ruleKind: RuleKind? = .dailyLimit,
            timeWindows: [TimeWindow] = [],
            isApplied: Bool = true,
            cooldownUsageMinutes: Int = defaultCooldownUsageMinutes,
            cooldownDurationMinutes: Int = defaultCooldownDurationMinutes,
            weekdayRules: [DayRule]? = nil,
            strictUntil: Date? = nil,
            strictStartedAt: Date? = nil
        ) {
            self.id = id
            self.name = name
            self.selection = selection.supportedTokenSelection
            self.dailyLimitMinutes = dailyLimitMinutes
            self.ruleKind = ruleKind
            self.timeWindows = timeWindows
            self.isApplied = isApplied
            self.cooldownUsageMinutes = cooldownUsageMinutes
            self.cooldownDurationMinutes = cooldownDurationMinutes
            self.weekdayRules = weekdayRules
            self.strictUntil = strictUntil
            self.strictStartedAt = strictStartedAt
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case selection
            case dailyLimitMinutes
            case ruleKind
            case timeWindows
            case isApplied
            case cooldownUsageMinutes
            case cooldownDurationMinutes
            case weekdayRules
            case strictUntil
            case strictStartedAt
        }

        // 새 필드는 어떤 페이로드에서도 throw하지 않아야 한다.
        // screenTimeGroups getter가 배열 전체를 try?로 디코딩하므로
        // 그룹 1개의 실패가 저장된 그룹 전체 소실로 이어진다.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            selection = try container.decode(FamilyActivitySelection.self, forKey: .selection)
            dailyLimitMinutes = try container.decode(Int.self, forKey: .dailyLimitMinutes)

            // 연장 불가 기간 필드는 isApplied 분기와 무관하게 항상 같은 non-throwing 패턴으로 디코딩한다
            // (구버전 페이로드는 키 부재 → nil). 분기 앞에서 한 번만 읽어 양쪽 분기에서 그대로 쓴다.
            strictUntil = (try? container.decodeIfPresent(Date.self, forKey: .strictUntil)) ?? nil
            strictStartedAt = (try? container.decodeIfPresent(Date.self, forKey: .strictStartedAt)) ?? nil

            if let isApplied = (try? container.decodeIfPresent(Bool.self, forKey: .isApplied)) ?? nil {
                self.isApplied = isApplied
                if let rawKind = (try? container.decodeIfPresent(String.self, forKey: .ruleKind)) ?? nil {
                    // 미래 버전의 미지 규칙 값은 보호가 끊기지 않도록 일일 한도로 fallback.
                    ruleKind = RuleKind(rawValue: rawKind) ?? .dailyLimit
                } else {
                    ruleKind = nil
                }
                timeWindows = (try? container.decodeIfPresent([TimeWindow].self, forKey: .timeWindows)) ?? nil ?? []
                cooldownUsageMinutes = (try? container.decodeIfPresent(Int.self, forKey: .cooldownUsageMinutes)) ?? nil ?? Self.defaultCooldownUsageMinutes
                cooldownDurationMinutes = (try? container.decodeIfPresent(Int.self, forKey: .cooldownDurationMinutes)) ?? nil ?? Self.defaultCooldownDurationMinutes
                let decodedWeekdayRules = (try? container.decodeIfPresent([DayRule].self, forKey: .weekdayRules)) ?? nil
                // 7개가 아니면 손상 페이로드 — weekdayRules만 버리고 base 규칙으로 폴백(그룹은 생존).
                weekdayRules = decodedWeekdayRules?.count == 7 ? decodedWeekdayRules : nil
            } else {
                // isApplied 키 부재 = 구버전 페이로드. 기존 사용자 그룹은 일일 한도 규칙이 이미 적용된 상태.
                isApplied = true
                ruleKind = .dailyLimit
                timeWindows = []
                cooldownUsageMinutes = Self.defaultCooldownUsageMinutes
                cooldownDurationMinutes = Self.defaultCooldownDurationMinutes
                weekdayRules = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(selection, forKey: .selection)
            try container.encode(dailyLimitMinutes, forKey: .dailyLimitMinutes)
            // isApplied는 신형 페이로드 마커 역할이므로 항상 기록한다.
            try container.encode(isApplied, forKey: .isApplied)
            try container.encodeIfPresent(ruleKind, forKey: .ruleKind)
            try container.encode(timeWindows, forKey: .timeWindows)
            try container.encode(cooldownUsageMinutes, forKey: .cooldownUsageMinutes)
            try container.encode(cooldownDurationMinutes, forKey: .cooldownDurationMinutes)
            // nil이면 키 자체가 없어 구버전과 왕복 안전.
            try container.encodeIfPresent(weekdayRules, forKey: .weekdayRules)
            // 연장 불가 기간: nil이면 키 생략 → 기존 페이로드 바이트 동일, 구버전 왕복 안전.
            try container.encodeIfPresent(strictUntil, forKey: .strictUntil)
            try container.encodeIfPresent(strictStartedAt, forKey: .strictStartedAt)
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
            return trimmed.isEmpty ? String(localized: "group.unnamed") : trimmed
        }

        /// 요일별 모드 여부. weekdayRules가 있으면 날짜마다 규칙이 달라진다.
        var usesWeekdayRules: Bool { weekdayRules != nil }

        /// 해당 날짜가 '제한 없음' 요일인지. 요일별 모드가 아니면 항상 false.
        func isUnrestricted(on date: Date, calendar: Calendar = .current) -> Bool {
            guard let rules = weekdayRules, rules.count == 7 else { return false }
            let index = WeekdayRulePolicy.weekdayIndex(for: date, calendar: calendar)
            return rules[index].kind == .unrestricted
        }

        /// 연장 불가 기간이 지금 유효한지. 만료 판정은 항상 lazy(저장값 청소 이벤트 없음) —
        /// 만료 후에도 strictUntil은 과거 날짜로 남고 이 함수가 false를 돌려준다.
        func isStrictLockActive(at now: Date = Date()) -> Bool {
            guard let strictUntil else { return false }
            return strictUntil > now
        }

        /// N일 연장 불가 기간의 만료 시각 = 오늘 포함 N일의 마지막 날 다음 자정 0시.
        /// 예: 7/12 낮에 days=3 → 7/15 00:00. days=1 → 내일 00:00.
        static func strictLockExpiry(days: Int, from now: Date = Date(), calendar: Calendar = .current) -> Date? {
            calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
        }

        /// 해당 날짜의 유효 규칙을 기존 규칙 필드에 투영한 사본을 반환한다.
        /// - 투영본은 항상 strict 필드(strictUntil/strictStartedAt)가 nil로 스트립된다. 연장 불가 기간은
        ///   집행 규칙이 아니므로 등록/churn 비교에서 제외한다 — 연장 불가 기간 판정은 반드시 원본 그룹에서.
        /// - weekdayRules == nil이면 strict만 스트립한 self 사본(비요일 그룹 통과).
        /// - 투영본은 weekdayRules가 nil로 스트립된다(등록 기록·churn 비교가 오늘 규칙만 보게).
        /// - 오늘이 '제한 없음'이면 ruleKind = nil → 기존 정책이 모니터링에서 자연 제외.
        /// - 7개가 아닌 비정상 배열은 디코더 폴백과 동일하게 base 규칙으로 취급(weekdayRules만 스트립).
        func resolved(on date: Date, calendar: Calendar = .current) -> ScreenTimeGroup {
            var copy = self
            // 연장 불가 기간은 집행 규칙이 아니므로 투영에서 항상 스트립한다 — 남으면 연장 불가 모드 적용가
            // 값 변경으로 보여 불필요한 모니터 재등록(churn)이 일어난다.
            copy.strictUntil = nil
            copy.strictStartedAt = nil
            guard let rules = weekdayRules else { return copy }
            copy.weekdayRules = nil
            guard rules.count == 7 else { return copy }

            let index = WeekdayRulePolicy.weekdayIndex(for: date, calendar: calendar)
            let today = rules[index]
            copy.dailyLimitMinutes = today.dailyLimitMinutes
            copy.timeWindows = today.timeWindows
            copy.cooldownUsageMinutes = today.cooldownUsageMinutes
            copy.cooldownDurationMinutes = today.cooldownDurationMinutes
            switch today.kind {
            case .unrestricted:
                copy.ruleKind = nil
            case .dailyLimit:
                copy.ruleKind = .dailyLimit
            case .timeWindows:
                copy.ruleKind = .timeWindows
            case .cooldown:
                copy.ruleKind = .cooldown
            }
            return copy
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
        String(localized: "group.defaultName \(index + 1)")
    }

    static func group(id: UUID) -> ScreenTimeGroup? {
        screenTimeGroups.first { $0.id == id }
    }

    /// id에 해당하는 그룹을 찾아 `now`의 유효 규칙으로 투영한 사본을 반환한다
    /// (extension tick 핸들러에서 오늘 규칙만 보게). 요일별 모드가 아니면 규칙 필드는 저장값 그대로다.
    /// **단 strict 필드는 항상 스트립된다** — 연장 불가 기간 판정에는 절대 쓰지 말 것(원본 `group(id:)`로).
    static func resolvedGroup(id: UUID, now: Date = Date()) -> ScreenTimeGroup? {
        group(id: id)?.resolved(on: now)
    }

    /// 적용된 그룹 중 연장 불가 기간이 유효한 그룹이 하나라도 있는지(전역 설정 on/off 판정용).
    static func hasActiveStrictLock(now: Date = Date()) -> Bool {
        screenTimeGroups.contains { $0.isApplied && $0.isStrictLockActive(at: now) }
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

    /// 일일 제한 모니터링이 처음 켜진 날(자정 기준).
    /// 그래프에서 "설치/제한 적용 이전(기록 없음)"과 "추적 중인데 0분"을 구분하는 기준.
    static var statsTrackingStartDate: Date? {
        get { defaults.object(forKey: Key.statsTrackingStartDate) as? Date }
        set { defaults.set(newValue, forKey: Key.statsTrackingStartDate) }
    }

    static func markStatsTrackingStartedIfNeeded(referenceDate: Date = Date()) {
        guard statsTrackingStartDate == nil else { return }
        statsTrackingStartDate = Calendar.current.startOfDay(for: referenceDate)
    }

    static var allDailyStats: [DailyStats] {
        Array(dailyStatsByDate.values)
    }

    static func calendarWeekRange(weekOffset: Int, firstWeekday: Int = SharedStore.weekStartDay) -> (start: Date, end: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = firstWeekday
        let todayStart = cal.startOfDay(for: Date())
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: todayStart)
        let thisWeekStart = cal.date(from: comps) ?? todayStart
        let weekStart = cal.date(byAdding: .weekOfYear, value: weekOffset, to: thisWeekStart) ?? thisWeekStart
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return (weekStart, weekEnd)
    }

    static func statsForCalendarWeek(weekOffset: Int, firstWeekday: Int = SharedStore.weekStartDay) -> [DailyStats] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = firstWeekday
        let (start, _) = calendarWeekRange(weekOffset: weekOffset, firstWeekday: firstWeekday)
        let dict = dailyStatsByDate
        return (0..<7).map { dayOffset in
            let date = cal.date(byAdding: .day, value: dayOffset, to: start) ?? start
            let key = dateKey(for: date)
            return dict[key] ?? DailyStats(dateKey: key)
        }
    }

    static func calendarMonthRange(monthOffset: Int) -> (start: Date, end: Date) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month], from: Date())
        comps.month = (comps.month ?? 1) + monthOffset
        let monthStart = cal.date(from: comps) ?? Date()
        var nextComps = cal.dateComponents([.year, .month], from: monthStart)
        nextComps.month = (nextComps.month ?? 1) + 1
        let nextMonthStart = cal.date(from: nextComps) ?? monthStart
        let monthEnd = cal.date(byAdding: .day, value: -1, to: nextMonthStart) ?? monthStart
        return (monthStart, monthEnd)
    }

    static func statsForCalendarMonth(monthOffset: Int) -> [DailyStats] {
        let cal = Calendar.current
        let (start, end) = calendarMonthRange(monthOffset: monthOffset)
        let dayCount = (cal.dateComponents([.day], from: start, to: end).day ?? 29) + 1
        let dict = dailyStatsByDate
        return (0..<dayCount).map { dayOffset in
            let date = cal.date(byAdding: .day, value: dayOffset, to: start) ?? start
            let key = dateKey(for: date)
            return dict[key] ?? DailyStats(dateKey: key)
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

    static func recordWalkAway() {
        updateStatsForToday { stats in
            stats.walkAwayCount += 1
        }
    }

    // MARK: - Analytics 대기 큐 (extension → 메인 앱)

    /// extension에서 발생한 분석 이벤트를 임시 보관하는 페이로드.
    /// extension은 Firebase를 링크하지 않으므로, 여기에 쌓아두면 메인 앱이 foreground 진입 시
    /// 드레인해서 전송한다. 값은 모두 문자열로 직렬화해 Codable 안정성을 확보한다.
    struct PendingAnalyticsEvent: Codable {
        let name: String
        let parameters: [String: String]
        let timestamp: Date
    }

    /// 큐 무한 증가 방지를 위한 상한. 초과 시 가장 오래된 항목부터 버린다.
    private static let pendingAnalyticsEventsCap = 200

    /// 큐 디코딩은 절대 throw하지 않는다(실패 시 빈 배열). key/구조 변경 시 하위 호환 주의.
    private static var pendingAnalyticsEvents: [PendingAnalyticsEvent] {
        get {
            guard let data = defaults.data(forKey: Key.pendingAnalyticsEvents) else { return [] }
            return (try? JSONDecoder().decode([PendingAnalyticsEvent].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Key.pendingAnalyticsEvents)
        }
    }

    static func enqueueAnalyticsEvent(name: String, parameters: [String: String] = [:]) {
        var events = pendingAnalyticsEvents
        events.append(PendingAnalyticsEvent(name: name, parameters: parameters, timestamp: Date()))
        if events.count > pendingAnalyticsEventsCap {
            events = Array(events.suffix(pendingAnalyticsEventsCap))
        }
        pendingAnalyticsEvents = events
    }

    /// Shield 진입. ruleKind = dailyLimit/timeWindows/cooldown.
    static func enqueueShieldHit(ruleKind: String) {
        enqueueAnalyticsEvent(name: "shield_hit", parameters: ["rule_kind": ruleKind])
    }

    /// Screen Time API 실패. context = 발생 지점, message = 오류 요약(100자 제한).
    static func enqueueScreenTimeError(context: String, message: String) {
        enqueueAnalyticsEvent(
            name: "screen_time_error",
            parameters: ["context": context, "message": String(message.prefix(100))]
        )
    }

    /// 큐를 비우고 보관 중이던 이벤트를 반환한다(메인 앱 드레인용).
    static func drainPendingAnalyticsEvents() -> [PendingAnalyticsEvent] {
        let events = pendingAnalyticsEvents
        if !events.isEmpty {
            defaults.removeObject(forKey: Key.pendingAnalyticsEvents)
        }
        return events
    }

    #if DEBUG
    static func clearDailyStatsForTesting() {
        defaults.removeObject(forKey: Key.dailyStatsByDate)
    }

    static func clearGroupStateForTesting() {
        defaults.removeObject(forKey: Key.screenTimeGroups)
        defaults.removeObject(forKey: Key.shieldedGroupIDs)
        defaults.removeObject(forKey: Key.overrideUntilByGroupID)
        defaults.removeObject(forKey: Key.cooldownUntilByGroupID)
        defaults.removeObject(forKey: Key.cooldownGenerationByID)
        defaults.removeObject(forKey: Key.overrideDiagnostics)
        defaults.removeObject(forKey: Key.lastRequestedUnlockApplicationToken)
        defaults.removeObject(forKey: Key.lastRequestedUnlockWebDomainToken)
        defaults.removeObject(forKey: Key.isShieldActive)
        defaults.removeObject(forKey: Key.isDailyMonitoringEnabled)
        defaults.removeObject(forKey: Key.oneMinuteUsedToday)
        defaults.removeObject(forKey: Key.oneMinuteCounterDate)
        defaults.removeObject(forKey: Key.dailyProtectionStateDate)
        defaults.removeObject(forKey: Key.usedTimeByGroupID)
        defaults.removeObject(forKey: Key.dailyBaselineByGroupID)
        defaults.removeObject(forKey: Key.cooldownBaselineByGroupID)
        defaults.removeObject(forKey: Key.lastRegisteredGroupsByID)
        defaults.removeObject(forKey: Key.lastRegisteredGenerationByID)
        defaults.removeObject(forKey: Key.usageBasedOverrideGroupIDs)
        defaults.removeObject(forKey: Key.overrideBaselineUsedTimeByGroupID)
        defaults.removeObject(forKey: Key.overrideGrantedMinutesByGroupID)
    }

    static func seedForPreview(_ stats: [DailyStats]) {
        var dict: [String: DailyStats] = [:]
        for stat in stats { dict[stat.dateKey] = stat }
        dailyStatsByDate = dict
        statsTrackingStartDate = dict.keys.min().flatMap { dateKeyFormatter.date(from: $0) }
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

    // MARK: - 쿨다운 상태

    /// 쿨다운 종료 시각. 쿨다운 중인 그룹만 항목이 존재한다.
    /// overrideUntilByGroupID와 동일한 [String:Date] JSON 인코딩.
    static var cooldownUntilByGroupID: [UUID: Date] {
        get {
            guard let data = defaults.data(forKey: Key.cooldownUntilByGroupID) else {
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
            defaults.set(data, forKey: Key.cooldownUntilByGroupID)
        }
    }

    /// usage 모니터 재등록 시 activity 이름 충돌 방지용 generation 카운터.
    /// daily의 lastRegisteredGenerationByID와 동일한 [String:Int] JSON 인코딩.
    static var cooldownGenerationByID: [UUID: Int] {
        get {
            guard let data = defaults.data(forKey: Key.cooldownGenerationByID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            guard let data = try? JSONEncoder().encode(raw) else {
                defaults.removeObject(forKey: Key.cooldownGenerationByID)
                return
            }
            defaults.set(data, forKey: Key.cooldownGenerationByID)
        }
    }

    // MARK: - 쿨다운 헬퍼

    /// 사용 예산 소진 → 쿨다운 시작. Extension threshold에서 호출 예정.
    static func startCooldown(until: Date, for groupID: UUID) {
        var map = cooldownUntilByGroupID
        map[groupID] = until
        cooldownUntilByGroupID = map
        markGroupShielded(groupID)
    }

    /// 쿨다운 종료 → 다음 사이클 generation 증가 후 반환.
    /// 타이머 종료/앱 복귀 재충전에서 호출 예정.
    @discardableResult
    static func endCooldownAndRecharge(for groupID: UUID) -> Int {
        var map = cooldownUntilByGroupID
        map.removeValue(forKey: groupID)
        cooldownUntilByGroupID = map
        unmarkGroupShielded(groupID)
        // 새 사이클은 사용량 0부터 시작한다(진행바·잠금 판정 기준).
        var used = usedTimeByGroupID
        used.removeValue(forKey: groupID)
        usedTimeByGroupID = used
        var baselines = cooldownBaselineByGroupID
        baselines.removeValue(forKey: groupID)
        cooldownBaselineByGroupID = baselines
        var gens = cooldownGenerationByID
        let next = (gens[groupID] ?? 0) + 1
        gens[groupID] = next
        cooldownGenerationByID = gens
        // 새 사이클은 사용량 0부터라 알림 단계도 초기화한다(다음 사이클에서 다시 50·90% 발송).
        clearUsageAlerts(for: groupID)
        // 진행 중이던 연장(광고/1분)도 함께 청산한다. usage 기반 override는 시간 만료로 정리되지
        // 않아(clearExpiredOverrides가 usage-based 제외) 연장분을 다 쓰기 전 휴식 종료를 넘겨
        // 살아남을 수 있고, 비우지 않으면 살아남은 override의 소진 tick이 handleOverrideTick에서
        // markGroupShielded를 호출해 cooldownUntil 없는 좀비 잠금(자정까지 해제 경로 없음)을 만든다.
        // 청산 후 늦게 도착하는 usageTick은 handleOverrideTick의 stale-tick 가드가 monitor stop만
        // 하고 재잠금 없이 흡수한다.
        clearOverride(for: groupID)
        return next
    }

    /// 쿨다운 그룹이 다른 규칙(일일/시간대)으로 전환될 때 쿨다운 휴식 사이클만 정리한다.
    /// `usedTime`은 보존한다(전환된 규칙이 이어서 사용). `cooldownUntil`/baseline을 비우고
    /// generation을 올려, 좀비 휴식 플래그(`isInCooldown` 고정)와 동일 activity 이름 재사용을 동시에 막는다.
    /// shield는 건드리지 않는다 — 전환된 규칙의 분기가 mark/unmark/resync로 결정한다.
    @discardableResult
    static func clearCooldownCycle(for groupID: UUID) -> Int {
        var map = cooldownUntilByGroupID
        map.removeValue(forKey: groupID)
        cooldownUntilByGroupID = map
        var baselines = cooldownBaselineByGroupID
        baselines.removeValue(forKey: groupID)
        cooldownBaselineByGroupID = baselines
        var gens = cooldownGenerationByID
        let next = (gens[groupID] ?? 0) + 1
        gens[groupID] = next
        cooldownGenerationByID = gens
        // 전환된 규칙이 새 기준으로 사용량 알림을 다시 보내도록 단계를 비운다(usedTime은 보존).
        clearUsageAlerts(for: groupID)
        return next
    }

    /// cooldownUntil이 존재하고 미래이면 쿨다운 중.
    static func isInCooldown(_ groupID: UUID, now: Date = Date()) -> Bool {
        guard let until = cooldownUntilByGroupID[groupID] else { return false }
        return until > now
    }

    /// 쿨다운 종료 예정 시각(없으면 nil).
    static func cooldownEnd(for groupID: UUID) -> Date? {
        cooldownUntilByGroupID[groupID]
    }

    /// 적용된 cooldown 그룹 중 cooldownUntil이 있고 <= now인(만료) 그룹 id 목록.
    /// 재충전 대상 조회용. 요일별 그룹은 base ruleKind가 오늘 규칙과 다르거나 nil일 수 있으므로
    /// 반드시 투영(resolved) 기준으로 판정한다 — 원본 기준이면 오늘 쿨다운인 요일 그룹이
    /// 자가치유 목록에서 빠져, 놓친 만료 휴식 잠금이 자정까지 잔존한다(좀비 잠금).
    static func expiredCooldownGroupIDs(now: Date = Date()) -> [UUID] {
        screenTimeGroups.compactMap { group in
            let today = group.resolved(on: now)
            guard today.ruleKind == .cooldown, today.isApplied else { return nil }
            guard let until = cooldownUntilByGroupID[group.id], until <= now else { return nil }
            return group.id
        }
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
        unmarkUsageBasedOverride(groupID)
        var baselines = overrideBaselineUsedTimeByGroupID
        baselines.removeValue(forKey: groupID)
        overrideBaselineUsedTimeByGroupID = baselines
        var grants = overrideGrantedMinutesByGroupID
        grants.removeValue(forKey: groupID)
        overrideGrantedMinutesByGroupID = grants
        // 연장 종료 → 이 연장에서 보낸 알림 단계도 비운다(다음 연장이 새로 50·90% 발송).
        clearOverrideAlerts(for: groupID)
    }

    @discardableResult
    static func clearAllOverrideState() -> Bool {
        let didChange = !overrideUntilByGroupID.isEmpty
            || !usageBasedOverrideGroupIDs.isEmpty
            || !overrideBaselineUsedTimeByGroupID.isEmpty
            || !overrideGrantedMinutesByGroupID.isEmpty

        overrideUntilByGroupID = [:]
        usageBasedOverrideGroupIDs = []
        overrideBaselineUsedTimeByGroupID = [:]
        overrideGrantedMinutesByGroupID = [:]
        overrideAlertSentByGroupID = [:]

        return didChange
    }

    /// override 시작 시점의 누적 사용 분(`usedTimeByGroupID` 스냅샷). UI 잔여 계산에 사용.
    static var overrideBaselineUsedTimeByGroupID: [UUID: Int] {
        get {
            guard let data = defaults.data(forKey: Key.overrideBaselineUsedTimeByGroupID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            guard let data = try? JSONEncoder().encode(raw) else {
                defaults.removeObject(forKey: Key.overrideBaselineUsedTimeByGroupID)
                return
            }
            defaults.set(data, forKey: Key.overrideBaselineUsedTimeByGroupID)
        }
    }

    /// 해당 override에서 부여된 분 (1분 연장은 1, 광고는 15).
    static var overrideGrantedMinutesByGroupID: [UUID: Int] {
        get {
            guard let data = defaults.data(forKey: Key.overrideGrantedMinutesByGroupID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            guard let data = try? JSONEncoder().encode(raw) else {
                defaults.removeObject(forKey: Key.overrideGrantedMinutesByGroupID)
                return
            }
            defaults.set(data, forKey: Key.overrideGrantedMinutesByGroupID)
        }
    }

    /// daily 모니터 등록 시점의 누적 사용 분(`usedTimeByGroupID` 스냅샷).
    /// freshDailyWindow는 등록 시점부터 측정하므로, extension은 이 baseline에 상대 틱 분을
    /// 더해 절대 사용량을 복원한다. 한도 변경 시 재등록해도 이미 쓴 분이 보존된다.
    static var dailyBaselineByGroupID: [UUID: Int] {
        get {
            guard let data = defaults.data(forKey: Key.dailyBaselineByGroupID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            guard let data = try? JSONEncoder().encode(raw) else {
                defaults.removeObject(forKey: Key.dailyBaselineByGroupID)
                return
            }
            defaults.set(data, forKey: Key.dailyBaselineByGroupID)
        }
    }

    /// 쿨다운 사용 예산 모니터 등록 시점의 누적 사용 분(`usedTimeByGroupID` 스냅샷).
    /// cooldownUsage 창은 등록 시점부터 측정하므로, extension은 이 baseline에 상대 tick 분을
    /// 더해 사이클 전체 사용량을 복원한다. 사용 시간 변경 시 이미 쓴 분이 보존된다.
    static var cooldownBaselineByGroupID: [UUID: Int] {
        get {
            guard let data = defaults.data(forKey: Key.cooldownBaselineByGroupID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            guard let data = try? JSONEncoder().encode(raw) else {
                defaults.removeObject(forKey: Key.cooldownBaselineByGroupID)
                return
            }
            defaults.set(data, forKey: Key.cooldownBaselineByGroupID)
        }
    }

    static func recordOverrideBaseline(groupID: UUID, baseline: Int, grantedMinutes: Int) {
        var baselines = overrideBaselineUsedTimeByGroupID
        baselines[groupID] = baseline
        overrideBaselineUsedTimeByGroupID = baselines
        var grants = overrideGrantedMinutesByGroupID
        grants[groupID] = grantedMinutes
        overrideGrantedMinutesByGroupID = grants
        // 새 연장 시작 → 직전 연장 잔여 알림 단계를 비워 이 연장에서 다시 50·90%를 보낸다.
        clearOverrideAlerts(for: groupID)
    }

    /// 사용량 기반 override 그룹. clearExpiredOverrides가 시간 만료로 정리하지 않도록 보호.
    static var usageBasedOverrideGroupIDs: Set<UUID> {
        get {
            guard let data = defaults.data(forKey: Key.usageBasedOverrideGroupIDs) else { return [] }
            let raw = (try? JSONDecoder().decode([String].self, from: data)) ?? []
            return Set(raw.compactMap(UUID.init(uuidString:)))
        }
        set {
            let raw = newValue.map(\.uuidString)
            guard let data = try? JSONEncoder().encode(raw) else {
                defaults.removeObject(forKey: Key.usageBasedOverrideGroupIDs)
                return
            }
            defaults.set(data, forKey: Key.usageBasedOverrideGroupIDs)
        }
    }

    static func markUsageBasedOverride(_ groupID: UUID) {
        var ids = usageBasedOverrideGroupIDs
        ids.insert(groupID)
        usageBasedOverrideGroupIDs = ids
    }

    static func unmarkUsageBasedOverride(_ groupID: UUID) {
        var ids = usageBasedOverrideGroupIDs
        ids.remove(groupID)
        usageBasedOverrideGroupIDs = ids
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
        usageBasedOverrideGroupIDs = []
        overrideBaselineUsedTimeByGroupID = [:]
        overrideGrantedMinutesByGroupID = [:]
        isShieldActive = false
        // 쿨다운도 일일 한도와 같이 자정 리셋(및 그룹 비움)에서 함께 해제된다.
        // generation은 monotonic이라 여기서 비우지 않는다.
        cooldownUntilByGroupID = [:]
        // 사용량 알림 단계는 매일 새로 시작한다(자정에 비움). pendingAnalyticsEvents와 달리
        // 보존 대상이 아니므로 여기서 함께 비운다.
        usageAlertSentByGroupID = [:]
        overrideAlertSentByGroupID = [:]
    }

    // MARK: - 릴레이 경과 시간 추적

    static var usedTimeByGroupID: [UUID: Int] {
        get {
            guard let data = defaults.data(forKey: Key.usedTimeByGroupID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
            return Dictionary(
                uniqueKeysWithValues: raw.compactMap { key, value in
                    guard let id = UUID(uuidString: key) else { return nil }
                    return (id, value)
                }
            )
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            let data = try? JSONEncoder().encode(raw)
            defaults.set(data, forKey: Key.usedTimeByGroupID)
        }
    }

    @discardableResult
    static func incrementAndGetUsedTime(for groupID: UUID) -> Int {
        var map = usedTimeByGroupID
        let next = (map[groupID] ?? 0) + 1
        map[groupID] = next
        usedTimeByGroupID = map
        return next
    }

    /// usedTime을 지정 값 이상으로만 올린다 (역행 방지). 현재 값을 반환.
    @discardableResult
    static func raiseUsedTime(to value: Int, for groupID: UUID) -> Int {
        var map = usedTimeByGroupID
        let next = max(map[groupID] ?? 0, value)
        map[groupID] = next
        usedTimeByGroupID = map
        return next
    }

    static var lastRegisteredGroupsByID: [UUID: ScreenTimeGroup]? {
        get {
            guard let data = defaults.data(forKey: Key.lastRegisteredGroupsByID) else { return nil }
            let raw = (try? JSONDecoder().decode([String: ScreenTimeGroup].self, from: data)) ?? [:]
            let pairs = raw.compactMap { key, value -> (UUID, ScreenTimeGroup)? in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, value)
            }
            return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.lastRegisteredGroupsByID)
                return
            }
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            let data = try? JSONEncoder().encode(raw)
            defaults.set(data, forKey: Key.lastRegisteredGroupsByID)
        }
    }

    /// 등록 churn 가드에서 한 그룹의 기록만 비운다. 모니터 재등록 실패 시 last==group이 남아
    /// syncDailyMonitoring의 `guard last != group`이 다음 foreground sync 재등록을 영구 스킵하는
    /// 것을 막는다(실패 그룹을 last==nil로 만들어 다음 sync가 즉시 재등록).
    static func clearRegistration(for groupID: UUID) {
        guard var registered = lastRegisteredGroupsByID else { return }
        registered.removeValue(forKey: groupID)
        lastRegisteredGroupsByID = registered
    }

    static func clearAllUsedTime() {
        defaults.removeObject(forKey: Key.usedTimeByGroupID)
        defaults.removeObject(forKey: Key.dailyBaselineByGroupID)
        defaults.removeObject(forKey: Key.cooldownBaselineByGroupID)
        lastRegisteredGroupsByID = nil
        lastRegisteredGenerationByID = [:]
    }

    static var lastRegisteredGenerationByID: [UUID: Int] {
        get {
            guard let data = defaults.data(forKey: Key.lastRegisteredGenerationByID) else { return [:] }
            let raw = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            guard let data = try? JSONEncoder().encode(raw) else {
                defaults.removeObject(forKey: Key.lastRegisteredGenerationByID)
                return
            }
            defaults.set(data, forKey: Key.lastRegisteredGenerationByID)
        }
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
        clearAllUsedTime()
        return true
    }

    /// shield/override/cooldownUntil 계열은 `validGroupIDs`(오늘 유효 그룹) 기준으로 prune하고,
    /// `cooldownGenerationByID`·`cooldownBaselineByGroupID`는 `cooldownProgressIDs`(존재하는 그룹 전체)
    /// 기준으로 prune한다(= 삭제 그룹만 지운다). 두 set을 나눈 이유: 오늘 '제한 없음'인 요일 그룹의
    /// cooldown generation이 지워지면 다음 등록이 gen 0을 재사용해 stop된 `cooldownUsage` activity 이름을
    /// 재사용 → 카운터 승계로 1분 만에 잠기는 회귀(ScreenTimeManager 주석 참조)가 재발한다. 비요일
    /// 사용처는 두 set에 같은 값(유효 그룹)을 넘겨 기존 동작을 유지한다.
    @discardableResult
    static func pruneShieldState(
        keepingGroupIDs validGroupIDs: Set<UUID>,
        keepingCooldownProgressGroupIDs cooldownProgressIDs: Set<UUID>
    ) -> Bool {
        let oldShieldedGroupIDs = shieldedGroupIDs
        let newShieldedGroupIDs = oldShieldedGroupIDs.intersection(validGroupIDs)

        let oldOverrides = overrideUntilByGroupID
        let newOverrides = oldOverrides.filter { validGroupIDs.contains($0.key) }
        let oldUsageBasedOverrides = usageBasedOverrideGroupIDs
        let newUsageBasedOverrides = oldUsageBasedOverrides.intersection(validGroupIDs)
        let oldOverrideBaselines = overrideBaselineUsedTimeByGroupID
        let newOverrideBaselines = oldOverrideBaselines.filter { validGroupIDs.contains($0.key) }
        let oldOverrideGrants = overrideGrantedMinutesByGroupID
        let newOverrideGrants = oldOverrideGrants.filter { validGroupIDs.contains($0.key) }

        let oldCooldownUntil = cooldownUntilByGroupID
        let newCooldownUntil = oldCooldownUntil.filter { validGroupIDs.contains($0.key) }

        let oldCooldownGen = cooldownGenerationByID
        let newCooldownGen = oldCooldownGen.filter { cooldownProgressIDs.contains($0.key) }
        let oldCooldownBaselines = cooldownBaselineByGroupID
        let newCooldownBaselines = oldCooldownBaselines.filter { cooldownProgressIDs.contains($0.key) }

        let didChange = newShieldedGroupIDs != oldShieldedGroupIDs
            || newOverrides.count != oldOverrides.count
            || newUsageBasedOverrides != oldUsageBasedOverrides
            || newOverrideBaselines.count != oldOverrideBaselines.count
            || newOverrideGrants.count != oldOverrideGrants.count
            || newCooldownUntil.count != oldCooldownUntil.count
            || newCooldownGen.count != oldCooldownGen.count
            || newCooldownBaselines.count != oldCooldownBaselines.count

        if didChange {
            shieldedGroupIDs = newShieldedGroupIDs
            overrideUntilByGroupID = newOverrides
            usageBasedOverrideGroupIDs = newUsageBasedOverrides
            overrideBaselineUsedTimeByGroupID = newOverrideBaselines
            overrideGrantedMinutesByGroupID = newOverrideGrants
            cooldownUntilByGroupID = newCooldownUntil
            cooldownGenerationByID = newCooldownGen
            cooldownBaselineByGroupID = newCooldownBaselines
        }

        return didChange
    }

    /// 적용된 시간대 차단 그룹에 대해 '지금이 시간대 안인지'를 판정해 shieldedGroupIDs에 반영한다.
    /// dailyLimit 그룹과 draft 그룹의 잠금 상태는 절대 건드리지 않는다.
    /// override 상태는 손대지 않으므로(시간대 안이라 marked여도 override 중이면 lockedGroups가 제외),
    /// 단 시간대 밖이면 override 여부와 무관하게 unmark한다.
    /// 요일별 그룹은 `resolved(on:now)` 투영으로 오늘 규칙을 본다 — 오늘이 시간대 규칙이 아닌 그룹
    /// (daily/쿨다운/제한 없음/draft)은 절대 건드리지 않는다.
    @discardableResult
    static func resyncTimeWindowLocks(now: Date = Date()) -> (changed: Bool, newlyLocked: Set<UUID>) {
        let minute = minuteOfDay(for: now)
        var ids = shieldedGroupIDs
        var newlyLocked = Set<UUID>()
        var changed = false

        for group in screenTimeGroups {
            let today = group.resolved(on: now)
            guard today.ruleKind == .timeWindows,
                  today.isApplied,
                  !today.timeWindows.isEmpty else { continue }

            let inside = today.timeWindows.contains { $0.contains(minuteOfDay: minute) }
            if inside {
                if ids.insert(group.id).inserted {
                    newlyLocked.insert(group.id)
                    changed = true
                }
            } else {
                if ids.remove(group.id) != nil {
                    changed = true
                }
            }
        }

        if changed {
            shieldedGroupIDs = ids
        }
        return (changed, newlyLocked)
    }

    static func markGroupShielded(_ groupID: UUID) {
        var ids = shieldedGroupIDs
        ids.insert(groupID)
        shieldedGroupIDs = ids
    }

    static func unmarkGroupShielded(_ groupID: UUID) {
        var ids = shieldedGroupIDs
        ids.remove(groupID)
        shieldedGroupIDs = ids
    }

    @discardableResult
    static func clearExpiredOverrides(now: Date = Date()) -> Bool {
        let overrides = overrideUntilByGroupID
        let usageBased = usageBasedOverrideGroupIDs
        // 사용량 기반 override는 시간 만료로 제거하지 않는다 (사용량 threshold 이벤트가 정리).
        let activeOverrides = overrides.filter { id, until in
            until > now || usageBased.contains(id)
        }
        guard activeOverrides.count != overrides.count else {
            return false
        }
        overrideUntilByGroupID = activeOverrides
        return true
    }

    static func groupsInOverride(now: Date = Date()) -> [ScreenTimeGroup] {
        clearExpiredOverrides(now: now)
        let overrides = overrideUntilByGroupID
        let usageBased = usageBasedOverrideGroupIDs
        return screenTimeGroups.filter { group in
            if usageBased.contains(group.id) { return true }
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
        let usageBased = usageBasedOverrideGroupIDs
        return screenTimeGroups.filter { group in
            guard ids.contains(group.id) else { return false }
            if usageBased.contains(group.id) { return false }
            return (overrides[group.id] ?? .distantPast) <= now
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

    /// 자정 기준 경과 분(0...1439). 시간대 차단 판정의 기준 값.
    static func minuteOfDay(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
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
