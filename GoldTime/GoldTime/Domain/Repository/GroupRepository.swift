
import Foundation

protocol GroupRepository {
    var screenTimeGroups: [ScreenTimeGroup] { get set }
    func defaultGroupName(for index: Int) -> String
    /// 연장 불가 모드 기능 사용 여부(설정 토글, 기본 Off). 그룹별 연장 불가 기간과 달리 앱 전역 설정이다.
    var isStrictLockEnabled: Bool { get set }
}
