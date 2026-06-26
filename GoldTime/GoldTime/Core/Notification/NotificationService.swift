//
//  NotificationService.swift
//  GoldTime
//
//  Local Notification 발송. ShieldAction 익스텐션에서 GoldTime 진입 유도용.
//

import Foundation
import UserNotifications

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

    /// 한도 임박 알림. 일일/쿨다운/연장 tick 콜백(extension)에서 발송. `percent`(50/90)로 문구를 분기하고
    /// `remainingMinutes`(한도까지 남은 분)를 본문에 넣는다. 짧은 한도의 단일 알림도 90으로 들어온다.
    static func scheduleUsageAlert(groupName: String, percent: Int, remainingMinutes: Int) {
        guard SharedStore.isUsageAlertEnabled else { return }
        let content = UNMutableNotificationContent()
        if percent >= 90 {
            content.title = String(localized: "notification.usage.almost.title")
            content.body = String(localized: "notification.usage.almost.body \(groupName) \(remainingMinutes)")
        } else {
            content.title = String(localized: "notification.usage.half.title")
            content.body = String(localized: "notification.usage.half.body \(groupName) \(remainingMinutes)")
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
        content.title = String(localized: "notification.recharge.title")
        content.body = String(localized: "notification.recharge.body \(groupName)")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 시간대 차단 5분 전 + 종료(재사용 가능) 알림을 매일 반복(`repeats:true`)으로 미리 예약한다.
    /// 시간대는 고정 시각이라 DeviceActivity activity를 늘리지 않고 캘린더 트리거로 건다(모니터링 상한 회피).
    /// 기존 시간대 알림을 prefix로 모두 지운 뒤 현재 그룹 구성으로 다시 건다(편집/삭제 반영).
    static func rescheduleTimeWindowAlerts(groups: [SharedStore.ScreenTimeGroup]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix(timeWindowAlertPrefix) }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
            }
            guard SharedStore.isUsageAlertEnabled else { return }
            for group in groups where group.ruleKind == .timeWindows && group.isApplied {
                let name = group.displayName
                for (index, window) in group.timeWindows.enumerated() {
                    scheduleTimeWindowAlert(
                        identifier: "\(timeWindowAlertPrefix)warn.\(group.id.uuidString).\(index)",
                        minuteOfDay: timeWindowAlertMinute(baseMinute: window.startMinuteOfDay, offset: -5),
                        title: String(localized: "notification.timeWindow.soon.title"),
                        body: String(localized: "notification.timeWindow.soon.body \(name)")
                    )
                    scheduleTimeWindowAlert(
                        identifier: "\(timeWindowAlertPrefix)end.\(group.id.uuidString).\(index)",
                        minuteOfDay: timeWindowAlertMinute(baseMinute: window.endMinuteOfDay, offset: 1),
                        title: String(localized: "notification.timeWindow.ended.title"),
                        body: String(localized: "notification.timeWindow.ended.body \(name)")
                    )
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

    private static func scheduleTimeWindowAlert(identifier: String, minuteOfDay: Int, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var components = DateComponents()
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
