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
}
