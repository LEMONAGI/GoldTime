
import Foundation

protocol ScreenTimeRepository {
    var isDailyMonitoringEnabled: Bool { get }

    func rolloverCounterIfNeeded()
    @discardableResult func reapplyShieldIfOverrideExpired() -> Bool
    func syncDailyMonitoring(groups: [ScreenTimeGroup]) throws
    func reconnectMonitoring() throws
    func validDailyMonitoringGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup]
    /// 현재 사용량 추적 모니터가 등록돼 있는 그룹 id 집합(`lastRegisteredGroupsByID` 기준).
    /// 자정 직전 편집 스킵·등록 실패 등으로 추적이 멈춘 그룹은 여기서 빠진다.
    func monitoredGroupIDs() -> Set<UUID>
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
