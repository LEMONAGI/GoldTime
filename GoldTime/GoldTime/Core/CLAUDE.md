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
- `releaseShield` override 측정창은 반드시 **date-less**(`[.hour,.minute,.second]`, end 23:59:59, `repeats:false`)여야 한다 — `freshDailyWindow`·`CooldownMonitor.usageSchedule`과 동일. intervalStart/End에 `.day`(절대 날짜) 컴포넌트를 넣으면 iOS가 threshold를 **즉시·배치 발화**시켜 연장 직후 m=2,3,4…가 한꺼번에 터진다(Apple Forums 확인, 회귀 커밋 `204a691`). 자정 넘김(`end<start`)은 `repeats:false`에서 불안정해 쓰지 않는다.
- **자정 직전(측정창 < 15분, 23:45부터) 연장 처리** — `startMonitoring`이 `intervalTooShort`로 실패하는 걸 모니터 없는 **시간기반 fallback**으로 우회한다(`overrideWindowTooShort` true면 `releaseShield`가 모니터 등록을 건너뛰고 `setOverride(until: 23:59:59)`만, **`markUsageBasedOverride`·`recordOverrideBaseline` 호출 안 함** → `clearExpiredOverrides`가 시간 만료로 정리, 재잠금은 foreground reapply + 자정 리셋이 보장). override는 grant 무관 **항상 자정까지**(보너스). 자정 근처에도 **광고는 그대로 필수**(스킵 없음). 통계 시간은 `extendGroup`에서 `recordAdUnlock`에 넘기는 초를 `overrideUntil-now`(=실제 해제 지속, 자정 근처는 자정까지 남은 시간)로 기록(횟수는 +1 유지). 경계 헬퍼 `overrideWindowTooShort`는 Core(`ScreenTimeManager`) 단일 출처로 두고 `ScreenTimeRepository`→`ExtendGroupUseCase`로 노출(1분 연장 비활성에 사용). UI 안내는 `withinNearMidnightNoticeWindow`로 **23:30부터 예고**하지만, 실제 fallback/1분 차단은 **23:45부터**만 적용한다. Home 카드는 granted 미기록을 신호로 이 override를 감지해 배지를 "23:59까지 추가 사용"으로, 남은 한도 바는 숨김(`HomeViewModel.isNearMidnightOverride`).
- **자정 직전(23:45부터) 그룹 편집도 같은 제약** — `syncDailyMonitoring`이 변경 그룹을 재등록할 때 daily(`freshDailyWindow`)·cooldown(`CooldownMonitor.usageSchedule`)은 `now~23:59:59` 1회성 창이라 15분 미만이면 `startMonitoring`이 `intervalTooShort`로 throw한다(timeWindow는 `repeats:true`라 영향 없음). 자정 직전엔 **모니터 등록을 건너뛰고 현재 usedTime 기준으로만 처리**하고 throw하지 않는다(미추적 15분 갭, 자정 후 첫 sync가 `lastRegisteredGroupsByID`에서 빠진 그룹을 fresh 재등록). daily는 `usedMinutes >= limit`이면 기존 `:326` 분기가 모니터 없이 잠그므로 그대로 안전하고, `needsMonitoringRestart`(used<limit) 분기만 자정 직전 스킵한다(stop한 generation 재사용 금지로 +1). **쿨다운은 daily와 달리 등록 시점 동기 잠금이 없어 새로 추가**했다(`cooldownEditAction` 순수 판정): 예산 소진(`used>=budget`)이면 평소 `enterCooldownRest`(휴식 진입+타이머), **자정 직전은 `markGroupShielded`만**(휴식 타이머 endtime 자정 넘김 회피 + 자정 `clearAllShieldState`가 예산 0으로 리셋해 재충전하므로 타이머 불필요). 휴식 중이면 `.register`(registerCooldownGroup이 early-return). `enterCooldownRest`는 편집 트리거라 분석 `shield_hit`을 남기지 않는다.
- `reconnectMonitoring()`은 `DeviceActivityCenter.stopMonitoring()`으로 **override activity까지 전부 멈춘다**. 사용량 기반 override 메타데이터(`usageBasedOverrideGroupIDs`, baseline/grant, `overrideUntil`)를 보존하면 해당 그룹이 계속 Shield union에서 제외되어 재잠금 이벤트가 다시 올 수 없다. 재연결 전에는 `SharedStore.clearAllOverrideState()`로 override만 비우고, `shieldedGroupIDs`/usedTime은 보존해 현재 규칙 기준으로 즉시 재쉴드되게 한다.
- **Analytics 대기 큐(`pendingAnalyticsEvents`)**: extension은 Firebase를 링크하지 않으므로(메인 앱 전용 `Core/Analytics/AnalyticsService`), extension에서 발생한 이벤트는 `SharedStore.enqueueShieldHit`/`enqueueScreenTimeError`로 큐에 쌓고 메인 앱이 `AppLifecycleViewModel.appDidBecomeActive` → `drainPendingAnalyticsEvents()`에서 Firebase로 전송한다. `ScreenTimeManager`(Core)도 Firebase를 모르므로 override 등록 실패를 이 큐(`enqueueScreenTimeError`)로 보낸다. 페이로드는 `[String:String]`만 담는 plain Codable(`PendingAnalyticsEvent`)이라 extension 빌드에 Firebase 의존성을 들이지 않는다. 디코딩은 절대 throw하지 않고(실패 시 빈 배열), 상한 200건. **자정 리셋 대상 아님**(`clearAllShieldState`에 넣지 말 것 — 드레인 전 이벤트가 소실됨). 메인 앱 흐름 이벤트는 큐를 거치지 않고 `AnalyticsRepository`(Domain)로 직접 로깅한다.
