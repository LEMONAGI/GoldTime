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
    /// 시간대 알림에 배정하는 최대 pending 슬롯. 현재 최대 구성의 롤링 계획은 35개라, 사용량 임박·아침
    /// 요약 같은 다른 로컬 알림을 위해 충분한 여유를 남긴다. 미래 설정 상한 변경 시의 최후 방어선이다.
    static let timeWindowAlertSoftLimit = 56
    private static let reservedNonTimeWindowNotificationSlots = 8
    private static let maximumPendingLocalNotifications = 64

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
        content.interruptionLevel = .timeSensitive
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
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 시간대 알림을 현재 구성으로 재예약한다.
    ///
    /// 비요일 그룹은 기존처럼 매일 반복으로 유지한다. 요일별 그룹은 주간 반복 7일치를 미리 쌓지 않고,
    /// 오늘의 알림과 내일 00:00~00:05 시작 시간대의 사전 경고만 날짜 포함 일회성으로 예약한다.
    /// 따라서 5그룹×3시간대×2종=오늘 30개에 다음 날 자정 경고가 더해져도 64개 제한 안에 머문다.
    /// 자정 하트비트가 주 갱신 경로이고, 규칙 저장·앱 활성화·BGTask의 보호 동기화가 보조 경로다.
    static func rescheduleTimeWindowAlerts(
        groups: [SharedStore.ScreenTimeGroup],
        now: Date = Date()
    ) {
        let calendar = Calendar.current
        let plans = timeWindowAlertPlans(
            groups: groups,
            isEnabled: SharedStore.isUsageAlertEnabled,
            now: now,
            calendar: calendar
        )
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            // 자정 하트비트가 00:00 종료 알림과 맞물릴 수 있다. 바로 발화할 요청을 이 시점에
            // 취소하면 "다시 사용 가능" 알림이 사라지므로, 임박한 요청은 이번 재예약에서 보존한다.
            let stale = requests.compactMap { request -> String? in
                guard request.identifier.hasPrefix(timeWindowAlertPrefix),
                      !shouldKeepImminentTimeWindowAlert(request, now: now) else { return nil }
                return request.identifier
            }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
            }

            // stale만 제거된다. 다른 GoldTime 알림과 발화 직전 보존 시간대 알림은 모두 슬롯을 점유한다.
            let occupiedPendingCount = requests.count - stale.count
            let capacity = max(
                0,
                min(
                    timeWindowAlertSoftLimit,
                    maximumPendingLocalNotifications
                        - occupiedPendingCount
                        - reservedNonTimeWindowNotificationSlots
                )
            )
            let selectedPlans = plans
                .sorted { lhs, rhs in
                    let lhsDate = lhs.nextFireDate(after: now, calendar: calendar)
                    let rhsDate = rhs.nextFireDate(after: now, calendar: calendar)
                    return lhsDate == rhsDate
                        ? lhs.identifier < rhs.identifier
                        : lhsDate < rhsDate
                }
                .prefix(capacity)

            if plans.count > selectedPlans.count {
                GTLog.timeWindow.error(
                    "시간대 알림 예약 축소 계획=\(plans.count, privacy: .public) 선택=\(selectedPlans.count, privacy: .public) 기존 pending=\(occupiedPendingCount, privacy: .public)"
                )
            } else if !plans.isEmpty {
                GTLog.timeWindow.notice(
                    "시간대 알림 예약 계획=\(plans.count, privacy: .public) 기존 pending=\(occupiedPendingCount, privacy: .public)"
                )
            }

            let pendingAdditions = DispatchGroup()
            for plan in selectedPlans {
                pendingAdditions.enter()
                scheduleTimeWindowAlert(plan: plan) { error in
                    if let error {
                        GTLog.timeWindow.error(
                            "시간대 알림 예약 실패 id=\(plan.identifier, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                        )
                    }
                    pendingAdditions.leave()
                }
            }

            // `add` 완료 후 실제 pending 목록을 다시 읽어, 시스템이 요청을 조용히 버린 경우도 관측한다.
            pendingAdditions.notify(queue: .global(qos: .utility)) {
                center.getPendingNotificationRequests { refreshed in
                    let scheduledIDs = Set(selectedPlans.map(\.identifier))
                    let actual = refreshed.reduce(into: 0) { count, request in
                        if scheduledIDs.contains(request.identifier) { count += 1 }
                    }
                    if actual != selectedPlans.count {
                        GTLog.timeWindow.error(
                            "시간대 알림 등록 불일치 선택=\(selectedPlans.count, privacy: .public) 실제=\(actual, privacy: .public)"
                        )
                    }
                }
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

    /// 자정 재예약이 막 발화할 시간대 알림을 취소하지 않도록 보존할지 판정한다.
    /// 1초 전까지 허용하는 것은 DeviceActivity 콜백·UserNotifications 등록의 미세한 시각 오차를 흡수하기
    /// 위함이고, 1분보다 먼 요청은 새 계획으로 교체해 편집·삭제 변경을 즉시 반영한다.
    nonisolated static func shouldKeepImminentTimeWindowAlert(
        fireDate: Date?,
        now: Date
    ) -> Bool {
        guard let fireDate else { return false }
        return fireDate >= now.addingTimeInterval(-1)
            && fireDate <= now.addingTimeInterval(60)
    }

    private static func shouldKeepImminentTimeWindowAlert(
        _ request: UNNotificationRequest,
        now: Date
    ) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return false }
        return shouldKeepImminentTimeWindowAlert(fireDate: trigger.nextTriggerDate(), now: now)
    }

    // MARK: - 시간대 알림 예약 계획(순수 계산 — IO 분리)

    /// 하나의 시간대 알림 예약 단위. IO(`scheduleTimeWindowAlert`)와 분리해 계산만 테스트한다.
    /// 비요일 규칙은 매일 반복, 요일별 규칙은 날짜가 포함된 일회성 예약을 쓴다.
    struct TimeWindowAlertPlan: Equatable {
        enum Phase: Equatable { case warn, end }
        enum Trigger: Equatable {
            case daily(hour: Int, minute: Int)
            case oneTime(Date)
        }

        let identifier: String
        let groupName: String
        let phase: Phase
        let trigger: Trigger

        fileprivate func nextFireDate(after now: Date, calendar: Calendar) -> Date {
            switch trigger {
            case .oneTime(let date):
                return date
            case .daily(let hour, let minute):
                return calendar.nextDate(
                    after: now,
                    matching: DateComponents(hour: hour, minute: minute),
                    matchingPolicy: .nextTime
                ) ?? .distantFuture
            }
        }
    }

    /// 현재 그룹 구성으로 예약할 시간대 알림 계획 목록을 만든다(순수 함수, IO 없음).
    /// - 비요일 그룹(weekdayRules == nil): 기존과 동일하게 base가 timeWindows면 매일 반복, 식별자는 index 기반.
    /// - 요일별 그룹: 오늘 timeWindows와 내일 자정 직전 사전 경고만 날짜 포함 일회성으로 만든다.
    nonisolated static func timeWindowAlertPlans(
        groups: [SharedStore.ScreenTimeGroup],
        isEnabled: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [TimeWindowAlertPlan] {
        guard isEnabled else { return [] }
        var plans: [TimeWindowAlertPlan] = []
        for group in groups where group.isApplied {
            let name = group.displayName
            if group.weekdayRules?.count == 7 {
                plans += weekdayGroupPlans(group: group, name: name, now: now, calendar: calendar)
            } else if group.ruleKind == .timeWindows {
                // 비요일 경로: 기존 index 기반 식별자·매일 반복 형태를 그대로 유지(회귀 방지).
                for (index, window) in group.timeWindows.enumerated() {
                    plans += dailyPlanPair(groupID: group.id, name: name, index: index, window: window)
                }
            }
        }
        return plans
    }

    /// 요일별 그룹 하나의 롤링 예약 계획. 오늘 유효 시간대의 5분 전·종료와, 내일 00:00~00:05에
    /// 시작하는 시간대의 5분 전만 날짜 포함 일회성으로 예약한다. 후자는 자정 하트비트보다 먼저
    /// 발화해야 하므로 전날에 선예약한다.
    private nonisolated static func weekdayGroupPlans(
        group: SharedStore.ScreenTimeGroup,
        name: String,
        now: Date,
        calendar: Calendar
    ) -> [TimeWindowAlertPlan] {
        var plans: [TimeWindowAlertPlan] = []
        let today = group.resolved(on: now, calendar: calendar)
        if today.ruleKind == .timeWindows {
            for window in today.timeWindows {
                plans += oneTimePlanPair(
                    groupID: group.id,
                    name: name,
                    window: window,
                    day: now,
                    now: now,
                    calendar: calendar
                )
            }
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return plans }
        let tomorrowRule = group.resolved(on: tomorrow, calendar: calendar)
        guard tomorrowRule.ruleKind == .timeWindows else { return plans }
        for window in tomorrowRule.timeWindows where window.startMinuteOfDay <= 5 {
            guard let warningDate = alertDate(
                on: tomorrow,
                minuteOfDay: window.startMinuteOfDay - 5,
                calendar: calendar
            ) else { continue }
            if let plan = oneTimePlan(
                groupID: group.id,
                name: name,
                phase: .warn,
                window: window,
                fireDate: warningDate,
                now: now,
                calendar: calendar
            ) {
                plans.append(plan)
            }
        }
        return plans
    }

    /// 비요일 그룹의 시간대 하나를 기존 매일 반복 알림 쌍으로 만든다.
    private nonisolated static func dailyPlanPair(
        groupID: UUID,
        name: String,
        index: Int,
        window: SharedStore.TimeWindow
    ) -> [TimeWindowAlertPlan] {
        let warn = timeWindowAlertMinute(baseMinute: window.startMinuteOfDay, offset: -5)
        let end = timeWindowAlertMinute(baseMinute: window.endMinuteOfDay, offset: 1)
        return [
            TimeWindowAlertPlan(
                identifier: "\(timeWindowAlertPrefix)warn.\(groupID.uuidString).\(index)",
                groupName: name,
                phase: .warn,
                trigger: .daily(hour: warn / 60, minute: warn % 60)
            ),
            TimeWindowAlertPlan(
                identifier: "\(timeWindowAlertPrefix)end.\(groupID.uuidString).\(index)",
                groupName: name,
                phase: .end,
                trigger: .daily(hour: end / 60, minute: end % 60)
            )
        ]
    }

    /// 요일별 그룹의 오늘 시간대 하나를 날짜 포함 일회성 알림 쌍으로 만든다.
    private nonisolated static func oneTimePlanPair(
        groupID: UUID,
        name: String,
        window: SharedStore.TimeWindow,
        day: Date,
        now: Date,
        calendar: Calendar
    ) -> [TimeWindowAlertPlan] {
        let alertSlots: [(TimeWindowAlertPlan.Phase, Int)] = [
            (.warn, window.startMinuteOfDay - 5),
            (.end, window.endMinuteOfDay + 1),
        ]
        return alertSlots.compactMap { phase, minuteOfDay in
            guard let fireDate = alertDate(on: day, minuteOfDay: minuteOfDay, calendar: calendar) else {
                return nil
            }
            return oneTimePlan(
                groupID: groupID,
                name: name,
                phase: phase,
                window: window,
                fireDate: fireDate,
                now: now,
                calendar: calendar
            )
        }
    }

    /// day의 시작에서 minuteOfDay만큼 이동해 날짜 넘김까지 정확히 반영한다.
    private nonisolated static func alertDate(
        on day: Date,
        minuteOfDay: Int,
        calendar: Calendar
    ) -> Date? {
        calendar.date(byAdding: .minute, value: minuteOfDay, to: calendar.startOfDay(for: day))
    }

    /// 지나간 알림은 만들지 않고, 날짜를 포함한 식별자로 같은 그룹·시간대의 일회성 요청 충돌을 막는다.
    private nonisolated static func oneTimePlan(
        groupID: UUID,
        name: String,
        phase: TimeWindowAlertPlan.Phase,
        window: SharedStore.TimeWindow,
        fireDate: Date,
        now: Date,
        calendar: Calendar
    ) -> TimeWindowAlertPlan? {
        guard fireDate > now else { return nil }
        let dateKey = dateKey(for: fireDate, calendar: calendar)
        let phaseName = phase == .warn ? "warn" : "end"
        return TimeWindowAlertPlan(
            identifier: "\(timeWindowAlertPrefix)\(phaseName).\(groupID.uuidString).\(window.startMinuteOfDay)-\(window.endMinuteOfDay).\(dateKey)",
            groupName: name,
            phase: phase,
            trigger: .oneTime(fireDate)
        )
    }

    private nonisolated static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func scheduleTimeWindowAlert(
        plan: TimeWindowAlertPlan,
        completion: @escaping (Error?) -> Void
    ) {
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
        content.interruptionLevel = .timeSensitive
        var components = DateComponents()
        let trigger: UNCalendarNotificationTrigger
        switch plan.trigger {
        case .daily(let hour, let minute):
            components.hour = hour
            components.minute = minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .oneTime(let date):
            components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
    }
}
