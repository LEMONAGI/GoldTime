
import Foundation

protocol NotificationRepository {
    func authorizationState() async -> NotificationPermissionState
    func requestAuthorizationIfNeeded() async -> NotificationPermissionState
    func scheduleDailyMorningNotification(extraMinutes: Int)

    /// 하루 요약(오전 9시) 알림 수신 여부. 기본값 On.
    var isDailyMorningNotificationEnabled: Bool { get }
    /// 하루 요약 알림 수신 여부를 바꾸고, 켜면 다음 오전 9시 알림을 즉시 예약, 끄면 예약을 취소한다.
    func setDailyMorningNotificationEnabled(_ enabled: Bool)
}
