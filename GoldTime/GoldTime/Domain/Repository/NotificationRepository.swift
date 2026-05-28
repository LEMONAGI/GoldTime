
import Foundation

protocol NotificationRepository {
    func authorizationState() async -> NotificationPermissionState
    func requestAuthorizationIfNeeded() async -> NotificationPermissionState
    func scheduleDailyMorningNotification(extraMinutes: Int)
}
