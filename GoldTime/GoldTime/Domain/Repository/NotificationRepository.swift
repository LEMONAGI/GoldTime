
import Foundation

protocol NotificationRepository {
    func authorizationState() async -> NotificationPermissionState
    func requestAuthorizationIfNeeded() async -> NotificationPermissionState
    /// 알림이 "시간 지정 요약"에 묶여 즉시 전달되지 않는지(time-sensitive 우회 반영).
    func isNotificationDeferredByScheduledSummary() async -> Bool
    func scheduleDailyMorningNotification(extraMinutes: Int)

    /// 하루 요약(오전 9시) 알림 수신 여부. 기본값 On.
    var isDailyMorningNotificationEnabled: Bool { get }
    /// 하루 요약 알림 수신 여부를 바꾸고, 켜면 다음 오전 9시 알림을 즉시 예약, 끄면 예약을 취소한다.
    func setDailyMorningNotificationEnabled(_ enabled: Bool)

    /// 사용·차단 알림(한도 임박, 차단 5분 전, 재사용 가능) 수신 여부. 기본값 On.
    var isUsageAlertEnabled: Bool { get }
    /// 사용·차단 알림 수신 여부를 바꾸고, 켜면 시간대 알림을 재예약, 끄면 예약을 취소한다.
    func setUsageAlertEnabled(_ enabled: Bool)
}
