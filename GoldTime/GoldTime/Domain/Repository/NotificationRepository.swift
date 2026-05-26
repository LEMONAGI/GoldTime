
import Foundation

protocol NotificationRepository {
    func authorizationState() async -> NotificationPermissionState
    func requestAuthorizationIfNeeded() async -> NotificationPermissionState
    func scheduleWeeklyStatsNotification(weekStartDay: Int)
    func scheduleDailyMorningNotification(extraMinutes: Int)
}
