//
//  NotificationService.swift
//  GoldTime
//
//  Local Notification 발송. ShieldAction 익스텐션에서 GoldTime 진입 유도용.
//

import Foundation
import UserNotifications
import os

/// 한도 임박 알림의 제한 종류 — 문구 분기용. 일일 한도/쿨다운 예산/연장(광고·1분) 시간.
enum UsageAlertKind {
    case daily, cooldown, override
}

enum NotificationService {
    static let openAppCategory = "GOLDTIME_OPEN"
    static let weeklyStatsIdentifier = "com.goldtime.weeklyStats"
    static let dailyMorningIdentifier = "com.goldtime.dailyMorning"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    /// 알림이 "시간 지정 요약"에 묶여 즉시 전달되지 않는 상태인지.
    /// time-sensitive 알림은 요약을 우회하므로, time-sensitive가 켜져 있으면 지연되지 않는다.
    static func isDeferredByScheduledSummary() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.scheduledDeliverySetting == .enabled else { return false }
        return settings.timeSensitiveSetting != .enabled
    }

    static func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .timeSensitive])
        case .authorized, .provisional:
            if settings.timeSensitiveSetting == .disabled {
                _ = try? await center.requestAuthorization(options: [.timeSensitive])
            }
        default:
            break
        }
        return await authorizationStatus()
    }

    /// 쉴드의 "GoldTime 가기" 버튼 탭 시 발송. 알림 탭 → 앱 진입.
    static func scheduleOpenAppNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.limitReached.title")
        content.body = String(localized: "notification.limitReached.body")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
        content.categoryIdentifier = openAppCategory

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 자정 `DeviceActivityMonitor.intervalDidStart`(주 경로)와 BGTask 폴백에서 호출.
    /// 오늘 아직 예약하지 않았을 때만, 확정된 어제 사용량으로 동적 문구를 만들어
    /// 그날 오전 9시 알림을 예약한다. 자정에 끝난 어제 데이터가 이미 확정돼 있으므로
    /// 발송 직전 생성 없이도 사용량 기반 문구가 정확하다.
    static func scheduleDailyMorningNotificationIfNeeded(now: Date = Date()) {
        guard SharedStore.isDailyMorningNotificationEnabled else { return }
        guard SharedStore.claimMorningNotificationSlot(now: now) else { return }
        scheduleDailyMorningNotificationUsingYesterdayUsage(now: now)
    }

    /// 확정된 어제 사용량으로 다음 오전 9시 알림을 예약한다. 슬롯 가드 없이 즉시 예약하므로
    /// 설정에서 하루 요약 알림을 다시 켰을 때 그날 오전 9시 알림을 곧바로 복구하는 데 쓴다.
    static func scheduleDailyMorningNotificationUsingYesterdayUsage(now: Date = Date()) {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let extraMinutes = SharedStore.stats(for: yesterday).totalUnlockedSeconds / 60
        let isWeekStart = calendar.component(.weekday, from: now) == SharedStore.weekStartDay
        scheduleDailyMorningNotification(extraMinutes: extraMinutes, isWeekStart: isWeekStart)
    }

    /// 예약된 오전 9시 알림(주간 통계 포함)을 취소한다. 하루 요약 알림을 끌 때 사용.
    static func cancelDailyMorningNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [dailyMorningIdentifier, weeklyStatsIdentifier]
        )
    }

    /// 알림 센터에 쌓인 전달된 알림을 모두 지운다. 앱 진입 시 호출 —
    /// extension(DeviceActivityMonitor·ShieldAction)이 보낸 알림도 같은 앱 소속이라 함께 지워진다.
    static func clearDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// 어제 추가 사용 분량에 따라 다음에 도래하는 오전 9시 알림을 예약한다.
    /// isWeekStart가 true이면 주간 통계 알림 내용으로 대체한다.
    static func scheduleDailyMorningNotification(extraMinutes: Int, isWeekStart: Bool = false) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyMorningIdentifier, weeklyStatsIdentifier])

        let content = UNMutableNotificationContent()
        content.sound = .default

        if isWeekStart {
            content.title = String(localized: "notification.morning.weekStart.title")
            content.body = String(localized: "notification.morning.weekStart.body")
        } else {
            switch extraMinutes {
            case 0:
                content.title = String(localized: "notification.morning.onTime.title")
                content.body = String(localized: "notification.morning.onTime.body")
            case 1...5:
                content.title = String(localized: "notification.morning.over.title \(extraMinutes)")
                content.body = String(localized: "notification.morning.over1.body")
            case 6...15:
                content.title = String(localized: "notification.morning.over.title \(extraMinutes)")
                content.body = String(localized: "notification.morning.over2.body")
            case 16...30:
                content.title = String(localized: "notification.morning.over.title \(extraMinutes)")
                content.body = String(localized: "notification.morning.over3.body")
            default:
                content.title = String(localized: "notification.morning.over.title \(extraMinutes)")
                content.body = String(localized: "notification.morning.over4.body")
            }
        }

        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: dailyMorningIdentifier, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    // MARK: - 사용·차단 알림 (isUsageAlertEnabled 토글)

    /// 시간대 차단 5분 전·종료(재사용 가능) 알림 식별자 접두사. 재예약/취소 시 이 prefix로 묶어 관리한다.
    static let timeWindowAlertPrefix = "goldtime.tw."

    /// 한도 임박 알림. 일일/쿨다운/연장 tick 콜백(extension)에서 발송. `kind`로 제한 종류를,
    /// `percent`(50/90)로 단계를 구분해 문구를 고른다. title에 그룹명, body에 남은 분(`remainingMinutes`).
    /// 짧은 한도의 단일 알림도 90으로 들어온다.
    static func scheduleUsageAlert(groupName: String, kind: UsageAlertKind, percent: Int, remainingMinutes: Int) {
        guard SharedStore.isUsageAlertEnabled else { return }
        let content = UNMutableNotificationContent()
        // 키는 정적 리터럴이라야 카탈로그 추출이 되므로 종류·단계별로 명시적으로 분기한다.
        switch (kind, percent >= 90) {
        case (.daily, false):
            content.title = String(localized: "notification.usage.daily.half.title \(groupName)")
            content.body = String(localized: "notification.usage.daily.half.body \(remainingMinutes)")
        case (.daily, true):
            content.title = String(localized: "notification.usage.daily.almost.title \(groupName)")
            content.body = String(localized: "notification.usage.daily.almost.body \(remainingMinutes)")
        case (.cooldown, false):
            content.title = String(localized: "notification.usage.cooldown.half.title \(groupName)")
            content.body = String(localized: "notification.usage.cooldown.half.body \(remainingMinutes)")
        case (.cooldown, true):
            content.title = String(localized: "notification.usage.cooldown.almost.title \(groupName)")
            content.body = String(localized: "notification.usage.cooldown.almost.body \(remainingMinutes)")
        case (.override, false):
            content.title = String(localized: "notification.usage.override.half.title \(groupName)")
            content.body = String(localized: "notification.usage.override.half.body \(remainingMinutes)")
        case (.override, true):
            content.title = String(localized: "notification.usage.override.almost.title \(groupName)")
            content.body = String(localized: "notification.usage.override.almost.body \(remainingMinutes)")
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 쿨다운 휴식 종료(재충전)·다시 사용 가능 알림. extension의 타이머 종료 콜백에서 발송.
    static func scheduleRechargeAvailable(groupName: String) {
        guard SharedStore.isUsageAlertEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.recharge.title \(groupName)")
        content.body = String(localized: "notification.recharge.body")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 시간대 차단 5분 전 + 종료(재사용 가능) 알림을 반복(`repeats:true`)으로 미리 예약한다.
    /// 시간대는 고정 시각이라 DeviceActivity activity를 늘리지 않고 캘린더 트리거로 건다(모니터링 상한 회피).
    /// 기존 시간대 알림을 prefix로 모두 지운 뒤 현재 그룹 구성으로 다시 건다(편집/삭제 반영).
    /// 요일별 그룹은 timeWindows인 요일에만 요일 트리거(주 1회)를, 비요일 그룹은 매일 반복을 예약한다.
    ///
    /// iOS는 앱당 pending 로컬 알림을 **64개**로 제한하고 초과분을 soonest-firing 우선으로 조용히
    /// 폐기한다. 요일별로 순진하게 예약하면 5그룹×7요일×3시간대×2종=210개까지 폭발하므로,
    /// `timeWindowAlertPlans`가 "7요일 전부 등장하는 시간대"를 매일 반복 1쌍으로 dedupe한다.
    /// dedupe 후에도 이론상 64를 넘길 수 있어 예약 직전 개수를 GTLog로 남긴다(하드 캡은 미구현).
    static func rescheduleTimeWindowAlerts(groups: [SharedStore.ScreenTimeGroup]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(timeWindowAlertPrefix) }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
            }
            let plans = timeWindowAlertPlans(groups: groups, isEnabled: SharedStore.isUsageAlertEnabled)
            if !plans.isEmpty {
                // 64개 제한 관측용(개수만). 초과 시 soonest-first로 시스템이 조용히 폐기.
                GTLog.timeWindow.notice("시간대 알림 예약 계획 \(plans.count, privacy: .public)개 (iOS pending 64 제한)")
            }
            for plan in plans {
                scheduleTimeWindowAlert(plan: plan)
            }
        }
    }

    /// 예약된 시간대 알림(5분 전·종료)을 모두 취소한다. 사용·차단 알림 토글을 끌 때 사용.
    static func cancelTimeWindowAlerts() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(timeWindowAlertPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    /// 시간대 알림용 분(0...1439)으로 정규화한다. `baseMinute + offset`을 하루(1440분)로 wrap해
    /// 5분 전(offset −5, 음수면 전날)·종료(offset +1, 1439분이면 자정)를 안전하게 감싼다.
    nonisolated static func timeWindowAlertMinute(baseMinute: Int, offset: Int) -> Int {
        let total = baseMinute + offset
        return ((total % 1440) + 1440) % 1440
    }

    /// 요일 트리거용으로 (요일 인덱스, 분)을 함께 wrap한다. `timeWindowAlertMinute`로 분을 구하고,
    /// 날짜가 넘어간 몫만큼 요일 인덱스를 ±1 wrap한다: 5분 전이 전날 23:5x로 넘어가면 weekday −1
    /// (일(0)→토(6)), 종료가 익일 00:00로 넘어가면 weekday +1(토(6)→일(0)). 분 wrap 로직은
    /// `timeWindowAlertMinute` 단일 출처를 재사용한다.
    nonisolated static func weekdayAlertComponents(
        weekdayIndex: Int,
        baseMinute: Int,
        offset: Int
    ) -> (weekdayIndex: Int, minuteOfDay: Int) {
        let minuteOfDay = timeWindowAlertMinute(baseMinute: baseMinute, offset: offset)
        // (base+offset − wrap)은 항상 1440의 배수라 정확히 나눠떨어진다(음수 포함).
        let dayShift = (baseMinute + offset - minuteOfDay) / 1440
        let wrappedIndex = ((weekdayIndex + dayShift) % 7 + 7) % 7
        return (wrappedIndex, minuteOfDay)
    }

    // MARK: - 시간대 알림 예약 계획(순수 계산 — IO 분리)

    /// 하나의 시간대 알림 예약 단위. IO(`scheduleTimeWindowAlert`)와 분리해 계산만 테스트한다.
    /// `weekday`가 nil이면 매일 반복(요일 컴포넌트 없음), 값이 있으면 주 1회 반복(Calendar weekday 1=일…7=토).
    struct TimeWindowAlertPlan: Equatable {
        enum Phase: Equatable { case warn, end }
        let identifier: String
        let groupName: String
        let phase: Phase
        let weekday: Int?
        let hour: Int
        let minute: Int
    }

    /// 시간대(start·end 분) 값 하나. 요일별 dedupe 비교 기준(TimeWindow.id는 요일 편집에서 복제되므로 값 비교).
    private struct WindowKey: Hashable {
        let start: Int
        let end: Int
    }

    /// 현재 그룹 구성으로 예약할 시간대 알림 계획 목록을 만든다(순수 함수, IO 없음).
    /// - 비요일 그룹(weekdayRules == nil): 기존과 동일하게 base가 timeWindows면 매일 반복, 식별자는 index 기반.
    /// - 요일별 그룹: timeWindows인 요일의 시간대만, 7요일 전부 등장하면 매일 반복 1쌍으로 dedupe(요일 접미사 없음),
    ///   미만이면 등장 요일마다 요일 트리거. 식별자는 (start-end) 값 + 요일 접미사로 충돌을 막는다.
    nonisolated static func timeWindowAlertPlans(
        groups: [SharedStore.ScreenTimeGroup],
        isEnabled: Bool
    ) -> [TimeWindowAlertPlan] {
        guard isEnabled else { return [] }
        var plans: [TimeWindowAlertPlan] = []
        for group in groups where group.isApplied {
            let name = group.displayName
            if let rules = group.weekdayRules, rules.count == 7 {
                plans += weekdayGroupPlans(groupID: group.id, name: name, rules: rules)
            } else if group.ruleKind == .timeWindows {
                // 비요일 경로: 기존 index 기반 식별자·매일 반복 형태를 그대로 유지(회귀 방지).
                for (index, window) in group.timeWindows.enumerated() {
                    let warn = timeWindowAlertMinute(baseMinute: window.startMinuteOfDay, offset: -5)
                    plans.append(TimeWindowAlertPlan(
                        identifier: "\(timeWindowAlertPrefix)warn.\(group.id.uuidString).\(index)",
                        groupName: name, phase: .warn, weekday: nil,
                        hour: warn / 60, minute: warn % 60))
                    let end = timeWindowAlertMinute(baseMinute: window.endMinuteOfDay, offset: 1)
                    plans.append(TimeWindowAlertPlan(
                        identifier: "\(timeWindowAlertPrefix)end.\(group.id.uuidString).\(index)",
                        groupName: name, phase: .end, weekday: nil,
                        hour: end / 60, minute: end % 60))
                }
            }
        }
        return plans
    }

    /// 요일별 그룹 하나의 예약 계획. timeWindows인 요일의 시간대 값을 모아 등장 요일 집합을 만들고,
    /// 7요일 전부면 매일 반복 1쌍, 미만이면 요일별 트리거로 펼친다.
    private nonisolated static func weekdayGroupPlans(
        groupID: UUID,
        name: String,
        rules: [SharedStore.DayRule]
    ) -> [TimeWindowAlertPlan] {
        var weekdaysByWindow: [WindowKey: Set<Int>] = [:]
        var order: [WindowKey] = []  // 첫 등장 순서 유지(결정론적 계획 — 테스트 안정)
        for index in 0..<7 where rules[index].kind == .timeWindows {
            var seenThisDay: Set<WindowKey> = []
            for window in rules[index].timeWindows {
                let key = WindowKey(start: window.startMinuteOfDay, end: window.endMinuteOfDay)
                guard !seenThisDay.contains(key) else { continue }  // 같은 날 중복 값은 한 번만
                seenThisDay.insert(key)
                if weekdaysByWindow[key] == nil {
                    weekdaysByWindow[key] = []
                    order.append(key)
                }
                weekdaysByWindow[key]?.insert(index)
            }
        }

        var plans: [TimeWindowAlertPlan] = []
        for key in order {
            let days = weekdaysByWindow[key] ?? []
            if days.count == 7 {
                plans += windowPlanPair(groupID: groupID, name: name, key: key, dayIndex: nil)
            } else {
                for dayIndex in days.sorted() {
                    plans += windowPlanPair(groupID: groupID, name: name, key: key, dayIndex: dayIndex)
                }
            }
        }
        return plans
    }

    /// 시간대 하나의 5분 전·종료 알림 쌍. `dayIndex`가 nil이면 매일 반복(요일 컴포넌트·접미사 없음),
    /// 값이 있으면 요일 wrap(`weekdayAlertComponents`)을 적용하고 식별자에 `.d<index>` 접미사를 붙인다.
    private nonisolated static func windowPlanPair(
        groupID: UUID,
        name: String,
        key: WindowKey,
        dayIndex: Int?
    ) -> [TimeWindowAlertPlan] {
        let suffix = dayIndex.map { ".d\($0)" } ?? ""
        let warn = alertSlot(dayIndex: dayIndex, baseMinute: key.start, offset: -5)
        let end = alertSlot(dayIndex: dayIndex, baseMinute: key.end, offset: 1)
        return [
            TimeWindowAlertPlan(
                identifier: "\(timeWindowAlertPrefix)warn.\(groupID.uuidString).\(key.start)-\(key.end)\(suffix)",
                groupName: name, phase: .warn, weekday: warn.weekday,
                hour: warn.minuteOfDay / 60, minute: warn.minuteOfDay % 60),
            TimeWindowAlertPlan(
                identifier: "\(timeWindowAlertPrefix)end.\(groupID.uuidString).\(key.start)-\(key.end)\(suffix)",
                groupName: name, phase: .end, weekday: end.weekday,
                hour: end.minuteOfDay / 60, minute: end.minuteOfDay % 60)
        ]
    }

    /// (요일 컴포넌트, 분)을 계산한다. dayIndex nil이면 요일 없는 매일 반복, 값이 있으면 요일 wrap 포함.
    private nonisolated static func alertSlot(
        dayIndex: Int?,
        baseMinute: Int,
        offset: Int
    ) -> (weekday: Int?, minuteOfDay: Int) {
        guard let dayIndex else {
            return (nil, timeWindowAlertMinute(baseMinute: baseMinute, offset: offset))
        }
        let c = weekdayAlertComponents(weekdayIndex: dayIndex, baseMinute: baseMinute, offset: offset)
        return (c.weekdayIndex + 1, c.minuteOfDay)  // Calendar weekday = index + 1
    }

    private static func scheduleTimeWindowAlert(plan: TimeWindowAlertPlan) {
        let content = UNMutableNotificationContent()
        switch plan.phase {
        case .warn:
            content.title = String(localized: "notification.timeWindow.soon.title \(plan.groupName)")
            content.body = String(localized: "notification.timeWindow.soon.body")
        case .end:
            content.title = String(localized: "notification.timeWindow.ended.title \(plan.groupName)")
            content.body = String(localized: "notification.timeWindow.ended.body")
        }
        content.sound = .default
        var components = DateComponents()
        components.hour = plan.hour
        components.minute = plan.minute
        // weekday만 추가(주 1회). .day/.year 등 다른 날짜 컴포넌트는 넣지 않는다(즉시·배치 발화 회피).
        if let weekday = plan.weekday {
            components.weekday = weekday
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
