
import Foundation

protocol ScreenTimeRepository {
    var isDailyMonitoringEnabled: Bool { get }

    func rolloverCounterIfNeeded()
    @discardableResult func reapplyShieldIfOverrideExpired() -> Bool
    func syncDailyMonitoring(groups: [ScreenTimeGroup]) throws
    func resetProtectionState() throws
    func validDailyMonitoringGroups(from groups: [ScreenTimeGroup]) -> [ScreenTimeGroup]
    func extendGroup(
        groupID: UUID,
        duration seconds: Int,
        source: ExtensionSource
    ) -> Result<GroupExtensionResult, ExtensionFailure>
}
