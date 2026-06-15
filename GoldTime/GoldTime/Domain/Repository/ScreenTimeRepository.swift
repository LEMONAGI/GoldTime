
import Foundation

protocol ScreenTimeRepository {
    var isDailyMonitoringEnabled: Bool { get }

    func rolloverCounterIfNeeded()
    @discardableResult func reapplyShieldIfOverrideExpired() -> Bool
    func syncDailyMonitoring(groups: [ScreenTimeGroup]) throws
    func reconnectMonitoring() throws
    func validDailyMonitoringGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup]
    func extendGroup(
        groupID: UUID,
        duration seconds: Int,
        source: ExtensionSource
    ) -> Result<GroupExtensionResult, ExtensionFailure>

    /// 자정까지 < 15분이라 정확한 사용량 추적(연장 모니터)이 불가능한 시점인지. = 23:45부터.
    func isNearMidnightOverrideCutoff(now: Date) -> Bool
    /// 자정 근처 안내 문구를 보여줄 구간인지. = 23:30부터(행동 변화 23:45 전 미리 알림).
    func isWithinNearMidnightNoticeWindow(now: Date) -> Bool
}
