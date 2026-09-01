
import Foundation

struct GroupRepositoryImpl: GroupRepository {
    var screenTimeGroups: [ScreenTimeGroup] {
        get { SharedStore.screenTimeGroups }
        set { SharedStore.screenTimeGroups = newValue }
    }

    func defaultGroupName(for index: Int) -> String {
        SharedStore.defaultGroupName(for: index)
    }

    /// 연장 불가 모드 옵션 토글(기본 On). 구 키(`SharedStore.isStrictLockEnabled`, 기본 Off 시절)가
    /// 아니라 **새 키** `isStrictLockOptionEnabled`를 읽는다 — 재사용하면 과거 Off 사용자가 업데이트
    /// 후 못 쓴다(하위 호환).
    var isStrictLockEnabled: Bool {
        get { SharedStore.isStrictLockOptionEnabled }
        set { SharedStore.isStrictLockOptionEnabled = newValue }
    }
}
