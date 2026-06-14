# Core 레이어 — 공유 상태/위험도 High

Apple Framework 래퍼와 싱글톤 서비스. ScreenTime, Auth, Notification, Ads, Persistence.
구성요소는 하위 폴더를 직접 보면 된다.

- import: Apple Framework 직접 허용(`FamilyControls`, `DeviceActivity`, `ManagedSettings`,
  `UserNotifications`, `GoogleMobileAds`). 다른 레이어에 의존하지 않음.
- `@Observable`·`shared` 싱글톤 허용(`AuthorizationService.shared`, `RewardedAdService.shared`).
  단 Domain/Presentation에서 이 서비스를 **직접 참조하면 안 됨**(프로토콜/UseCase 경유).
- 위험도 **High** → 직렬로 처리하고 검증 메모를 남긴다.

## SharedStore 계약 (코드만 봐선 모르는 것)

`Core/Persistence/SharedStore.swift` = 메인 앱과 3개 extension이 함께 쓰는 App Group
UserDefaults(suite `group.com.goldtime.shared`).

- **key 이름·Codable 구조 변경 = 설치된 앱 상태 마이그레이션**. 의도된 migration/reset이
  없으면 하위 호환을 우선한다. key 변경은 가볍게 하지 말 것.
- **`ScreenTimeGroup`의 새 필드는 custom Codable로 절대 throw하지 않게** 디코딩한다.
  `screenTimeGroups` getter가 배열 전체를 `try?`로 디코딩하므로, 그룹 1개의 디코딩 실패가
  **전체 그룹 소실**로 이어진다.
- 구버전 페이로드(`isApplied` 키 없음)는 "일일 한도 + 적용됨"으로 디코딩되어야 한다.
- `resyncTimeWindowLocks(now:)`는 시간대 잠금을 `shieldedGroupIDs`에 반영하며 일일 한도/draft
  그룹은 건드리지 않는다. 호출 시점은 `docs/agent/critical-flows.md`의 "시간대 차단 흐름" 참조.

## ScreenTimeManager (Core/ScreenTime)

- 주요 진입: `syncDailyMonitoring(groups:)`, `consumeOneMinute(for:)`, `consumeAdReward(for:)`,
  `releaseShield(forSeconds:groupID:)`, `rolloverCounterIfNeeded()`,
  `reapplyShieldIfOverrideExpired`.
- Apple framework 호출부는 **얇게** 유지하고 복잡한 조건 판단을 넣지 않는다(테스트 가능한
  판단 로직은 분리). 런타임 동작은 실기기 검증 필수 — 시뮬레이터로 완료 처리 금지.

## Extension과의 관계

Extension은 메인 앱 API에 의존하지 않고 `SharedStore` + 알림으로만 상태를 주고받는다.
중앙화 가능한 상태 로직을 앱과 extension에 중복 구현하지 말 것.

전체 흐름(Daily Monitoring / Shield / 광고 / 1분 연장)은 `docs/agent/critical-flows.md`.

## 주의사항 (작업 중 발견 시 누적)

- 쿨다운 모드 등록은 `CooldownMonitor`(이 폴더, `ScreenTime/`)에 있고 **메인 앱·extension 두 타겟에 모두 포함**된다(extension은 ScreenTimeManager를 못 보므로 재충전 등록을 위해 공유). 이 파일을 옮기거나 import를 늘릴 때 extension 빌드 영향을 확인할 것.
- 쿨다운 사용량은 `usedTimeByGroupID`를 daily와 공유한다(한 그룹은 daily이거나 cooldown이지 둘 다는 아님). 사이클 시작 시 0으로 리셋해야 진행바·잠금 판정이 맞음 → `endCooldownAndRecharge`가 usedTime을 비운다.
- 쿨다운도 자정 리셋 대상이다. `clearAllShieldState`가 `cooldownUntilByGroupID`를 비우므로, 자정 보존이 필요한 새 상태를 여기 추가하지 말 것. `cooldownGenerationByID`는 monotonic이라 의도적으로 비우지 않는다.
- `releaseShield` override 측정창은 반드시 **date-less**(`[.hour,.minute,.second]`, end 23:59:59, `repeats:false`)여야 한다 — `freshDailyWindow`·`CooldownMonitor.usageSchedule`과 동일. intervalStart/End에 `.day`(절대 날짜) 컴포넌트를 넣으면 iOS가 threshold를 **즉시·배치 발화**시켜 연장 직후 m=2,3,4…가 한꺼번에 터진다(Apple Forums 확인, 회귀 커밋 `204a691`). 자정 직전(끝 ~15분) 연장은 측정창이 15분 미만이라 등록 실패할 수 있으나(1.0.2 동작), 자정 넘김(`end<start`) 보장은 `repeats:false`에서 불안정해 적용하지 않는다.
