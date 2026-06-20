# Core 레이어 — 공유 상태/위험도 High

Apple Framework 래퍼와 싱글톤 서비스. ScreenTime, Auth, Notification, Ads, Persistence.
구성요소는 하위 폴더를 직접 보면 된다.

- import: Apple Framework 직접 허용(`FamilyControls`, `DeviceActivity`, `ManagedSettings`,
  `UserNotifications`, `GoogleMobileAds`). 다른 레이어에 의존하지 않음.
- `@Observable`·`shared` 싱글톤 허용(`AuthorizationService.shared`, `RewardedAdService.shared`).
  단 Domain/Presentation에서 이 서비스를 **직접 참조하면 안 됨**(프로토콜/UseCase 경유).
- 위험도 **High** → 직렬로 처리하고 검증 메모를 남긴다.

## GTLog — 디버그 OSLog (`Core/Logging/GTLogger.swift`)

그룹별·잠금 방식별로 사용량 측정/잠금/해제가 실제 일어나는지 추적하는 `os.Logger` 래퍼.
`print`이 아니라 OSLog인 이유: 강제종료/재부팅 후에도 시스템 로그에 보존돼 사후 확인이 된다
(extension은 별도 프로세스라 `print`이 Xcode에 거의 안 잡힘).

- subsystem `com.nagi.GoldTime` 고정(extension의 `Bundle.main`은 extension id라 고정값 사용).
  카테고리: `DailyLimit` / `Cooldown` / `TimeWindow` / `Override` / `Shield` / `Activity`
  (`Activity`는 DeviceActivity 콜백 진입점 raw 추적 = tick 도착 여부 자체).
- **`GTLog`를 쓰는 파일은 반드시 `import os`** 한다. `\(x, privacy: .public)` interpolation은
  `os`의 `OSLogInterpolation`이라, GTLog 정의 파일에만 import가 있고 사용처에 없으면
  `instance method 'notice' is not available due to missing import of defining module 'os'`로
  **빌드 실패**(SourceKit은 "Extra argument 'privacy'"로 보임). 메인 앱·extension 모두 해당.
- **프라이버시**: `FamilyActivitySelection`·application/webDomain 토큰은 절대 로깅 금지(opaque/민감,
  개수만). 그룹 이름·UUID·분 수·임계값은 디버깅에 필요하므로 `privacy: .public` 명시(기본은 마스킹).
- 확인: 기기 연결 후 Console.app 필터 `subsystem:com.nagi.GoldTime`, 또는
  `log show --last 30m --predicate 'subsystem == "com.nagi.GoldTime"'`(강제종료 후 보존 확인).
- Presentation은 Core 직접 참조 금지라 GTLog를 쓰지 않는다(측정/잠금/해제 로깅은 Core+extension에만).

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

- ATT 버튼의 로딩은 UMP 동의와 ATT 응답까지만 기다린다. `MobileAds.start()` 완료 콜백은 네트워크·WebKit
  프로세스 콜드 스타트로 오래 걸릴 수 있으므로 온보딩 화면 전환을 막지 말고, `ConsentService`가
  소유한 단일 Task에서 SDK 초기화와 광고 프리로드를 이어간다. 온보딩 직후 `.withConsentFlow()`도
  실행되므로 동의 흐름 자체도 Task로 단일화해 UMP/ATT 중복 요청을 막는다.
- **GDPR 동의 철회는 `ConsentService.presentPrivacyOptions()`**(UMP `presentPrivacyOptionsForm`).
  온보딩 1회 동의(`consentFlowTask` 단일화)와 달리 사용자 명시 액션이라 Task 큐를 거치지 않고
  매번 즉시 띄운다. 설정 화면 노출 여부는 `isPrivacyOptionsRequired`(`privacyOptionsRequirementStatus
  == .required`)로 EEA/UK에서만 true → 비대상 지역은 행이 숨겨진다. **AdMob 콘솔에 GDPR 메시지가
  게시돼 있어야** 폼이 뜨고 실기기에서만 검증 가능(시뮬레이터 무의미). 앱 `PrivacyInfo.xcprivacy`는
  `NSPrivacyTracking=true`, tracking domains는 비움(SDK 매니페스트가 선언; 잘못 넣으면 ATT 미동의
  시 정상 연결도 차단) — 실제 도메인/수집항목은 Archive→Generate Privacy Report로 검증·보강.
- `syncDailyMonitoring`의 `newRegistered`는 빈 dict가 아니라 **기존 등록 기록의 복사본**(`lastRegistered.filter { valid }`)으로 시작해 마지막에 `lastRegisteredGroupsByID`로 통째 persist된다. 그래서 등록 catch(daily/timeWindow/cooldown)는 실패 시 `newRegistered.removeValue(forKey: group.id)`로 **stale 항목을 비워야** `monitoredGroupIDs()` 오표시(미추적인데 추적 중으로 보임)를 막는다. 등록 자체를 건너뛰는 자정 직전 분기(`.lockUntilMidnight`/`.skipUntracked`)도 동일 관용구를 쓴다. **로컬 dict 제거이지 `SharedStore.clearRegistration`이 아니다** — sync 도중 SharedStore를 건드려도 마지막 persist가 덮어쓴다(`clearRegistration`은 extension 타이머 종료 재충전처럼 sync 밖 경로 전용). 편집 경로는 `last(stale) != group(new)`이라 다음 sync가 자동 재시도하므로 영구 공백은 아니다.
- `MonitoringBackgroundTask`(자정 BGTask, fallback 재연결)는 `syncDailyMonitoring` 실패를 `try?`로 삼키지 말고 `enqueueScreenTimeError(context:"backgroundReconnect")` 기록 + `setTaskCompleted(success:false)`로 관측 가능하게 둔다.
- 쿨다운 모드 등록은 `CooldownMonitor`(이 폴더, `ScreenTime/`)에 있고 **메인 앱·extension 두 타겟에 모두 포함**된다(extension은 ScreenTimeManager를 못 보므로 재충전 등록을 위해 공유). 이 파일을 옮기거나 import를 늘릴 때 extension 빌드 영향을 확인할 것.
- **휴식 중(`isInCooldown`) 쿨다운 그룹 편집 시 현재 휴식을 보존한다.** `syncDailyMonitoring`의 stale 정리는 변경된 쿨다운 그룹의 `cooldownTimer`까지 stop하면 안 된다 — `.keepCooldownRest`의 `registerCooldownGroup`이 휴식 중 early-return해서 타이머가 재등록되지 않아 휴식 종료(`handleCooldownTimerEnded`)가 영영 안 온다. stop 대상은 순수 함수 `cooldownActivitiesToStop`이 결정한다: 휴식 중이면 `cooldownUsage`만(타이머 보존), 그 외(삭제/규칙 전환/휴식 아님)는 usage+timer 둘 다. 변경된 설정은 휴식 종료 후 재충전 시점부터 적용된다(다음 사이클).
- 쿨다운 사용량은 `usedTimeByGroupID`를 daily와 공유한다(한 그룹은 daily이거나 cooldown이지 둘 다는 아님). 사용 시간 변경 재등록 시 이미 쓴 분을 보존하려고 `cooldownBaselineByGroupID`에 등록 시점 usedTime을 저장하고 extension tick에서 `baseline + minute`으로 복원한다. 사이클 시작 시 0으로 리셋해야 진행바·잠금 판정이 맞음 → `endCooldownAndRecharge`가 usedTime과 cooldown baseline을 비운다.
- **쿨다운 휴식 중 그룹을 다른 규칙(일일/시간대)으로 전환하면 휴식 사이클(`cooldownUntilByGroupID`)을 반드시 정리해야 한다.** `pruneShieldState`는 **삭제/무효화된 그룹만** 쿨다운 상태를 비우고 규칙만 바뀐 valid 그룹은 건드리지 않는다 → 좀비 휴식 플래그가 남는다. 그 상태로 다시 쿨다운으로 돌아오면 `cooldownEditAction`이 `isInCooldown=true`를 보고 `.keepCooldownRest`를 반환하고 `registerCooldownGroup`이 early-return → **어떤 모니터도 등록되지 않아 측정·재잠금이 영영 안 됨**(휴식 타이머는 전환 시 `cooldownActivitiesToStop`이 이미 stop했으므로 휴식 종료도 안 옴). `syncDailyMonitoring`은 `previousCooldownGroupIDs ∩ valid − validCooldown`(= 쿨다운을 떠난 그룹)에 대해 `SharedStore.clearCooldownCycle`을 호출해 정리한다 — **usedTime은 보존**(전환된 규칙이 이어 사용), `cooldownUntil`·baseline은 비우고 generation은 +1(stop한 `cooldownUsage` activity 이름 재사용 → 즉시 발화 회귀 `204a691` 방지). shield는 건드리지 않고 전환된 규칙 분기가 결정. `clearCooldownCycle` ≠ `endCooldownAndRecharge`(후자는 usedTime까지 0으로 비워 전환 규칙이 이미 쓴 시간을 잃음).
- 쿨다운도 자정 리셋 대상이다. `clearAllShieldState`가 `cooldownUntilByGroupID`를 비우므로, 자정 보존이 필요한 새 상태를 여기 추가하지 말 것. `cooldownGenerationByID`는 monotonic이라 의도적으로 비우지 않는다. 휴식 종료 시각은 `CooldownMonitor.cooldownEnd`에서 `min(now+duration, 오늘 23:59:59)`로 clamp해 `cooldownUntil` 저장값과 `cooldownTimer` intervalEnd를 다음날로 넘기지 않는다.
- `releaseShield` override 측정창은 반드시 **date-less**(`[.hour,.minute,.second]`, end 23:59:59, `repeats:false`)여야 한다 — `freshDailyWindow`·`CooldownMonitor.usageSchedule`과 동일. intervalStart/End에 `.day`(절대 날짜) 컴포넌트를 넣으면 iOS가 threshold를 **즉시·배치 발화**시켜 연장 직후 m=2,3,4…가 한꺼번에 터진다(Apple Forums 확인, 회귀 커밋 `204a691`). 자정 넘김(`end<start`)은 `repeats:false`에서 불안정해 쓰지 않는다.
- **자정 직전(측정창 < 15분, 23:45부터) 연장 처리** — `startMonitoring`이 `intervalTooShort`로 실패하는 걸 모니터 없는 **시간기반 fallback**으로 우회한다(`overrideWindowTooShort` true면 `releaseShield`가 모니터 등록을 건너뛰고 `setOverride(until: 23:59:59)`만, **`markUsageBasedOverride`·`recordOverrideBaseline` 호출 안 함** → `clearExpiredOverrides`가 시간 만료로 정리, 재잠금은 foreground reapply + 자정 리셋이 보장). override는 grant 무관 **항상 자정까지**(보너스). 자정 근처에도 **광고는 그대로 필수**(스킵 없음). 통계 시간은 `extendGroup`에서 `recordAdUnlock`에 넘기는 초를 `overrideUntil-now`(=실제 해제 지속, 자정 근처는 자정까지 남은 시간)로 기록(횟수는 +1 유지). 경계 헬퍼 `overrideWindowTooShort`는 Core(`ScreenTimeManager`) 단일 출처로 두고 `ScreenTimeRepository`→`ExtendGroupUseCase`로 노출(1분 연장 비활성에 사용). UI 안내는 `withinNearMidnightNoticeWindow`로 **23:30부터 예고**하지만, 실제 fallback/1분 차단은 **23:45부터**만 적용한다. Home 카드는 granted 미기록을 신호로 이 override를 감지해 배지를 "23:59까지 추가 사용"으로, 남은 한도 바는 숨김(`HomeViewModel.isNearMidnightOverride`).
- **자정 직전(23:45부터) 그룹 편집도 같은 제약** — `syncDailyMonitoring`이 변경 그룹을 재등록할 때 daily(`freshDailyWindow`)·cooldown(`CooldownMonitor.usageSchedule`)은 `now~23:59:59` 1회성 창이라 15분 미만이면 `startMonitoring`이 `intervalTooShort`로 throw한다(timeWindow는 `repeats:true`라 영향 없음). 자정 직전엔 **모니터 등록을 건너뛰고 현재 usedTime 기준으로만 처리**하고 throw하지 않는다(미추적 15분 갭, 자정 후 첫 sync가 `lastRegisteredGroupsByID`에서 빠진 그룹을 fresh 재등록). daily는 `usedMinutes >= limit`이면 기존 `:326` 분기가 모니터 없이 잠그므로 그대로 안전하고, `needsMonitoringRestart`(used<limit) 분기만 자정 직전 스킵한다(stop한 generation 재사용 금지로 +1). **쿨다운은 daily와 달리 등록 시점 동기 잠금이 없어 새로 추가**했다(`cooldownEditAction` 순수 판정): 예산 소진(`used>=budget`)이면 평소 `enterCooldownRest`(휴식 진입+타이머), **자정 직전은 `markGroupShielded`만**(휴식 타이머 endtime 자정 넘김 회피 + 자정 `clearAllShieldState`가 예산 0으로 리셋해 재충전하므로 타이머 불필요). 휴식 중이면 `.keepCooldownRest`(registerCooldownGroup이 early-return), 예산이 남은 전환이면 `.registerAvailable`에서 기존 daily 잠금도 `unmarkGroupShielded`로 풀고 남은 예산만 측정한다. `enterCooldownRest`는 편집 트리거라 분석 `shield_hit`을 남기지 않는다.
- **`rechargeExpiredCooldowns`(foreground 자가치유, 타이머 콜백 놓친 만료 휴식 정리·재충전)의 등록 실패는 `try?`로 삼키지 말 것.** 정상 타이머 경로(`handleCooldownTimerEnded`)와 동일하게 처리한다: (0) **재충전 시 휴식 타이머뿐 아니라 직전 사이클의 `cooldownUsage(generation-1)`도 함께 stop**한다(예산 체크 전, 무조건) — 안 멈추면 stale activity가 모니터링 슬롯을 잠식해 반복 자가치유 시 `excessiveActivities` 위험. (1) **자정 직전(`overrideWindowTooShort`)은 등록 스킵 + 로그 안 함** — `usageSchedule(now~23:59:59)` <15분이라 `intervalTooShort`가 의도된 동작(`syncDailyMonitoring`의 `.skipUntracked`와 동일, 자정 리셋이 재충전). 여기서 에러를 큐에 넣으면 정상 동작을 거짓 에러로 오염시킨다. (2) **그 외 진짜 실패는 `enqueueScreenTimeError("cooldownRecharge")` + `lastRegisteredGroupsByID[groupID]` 제거**. 이 경로는 churn 가드(`syncDailyMonitoring:256` `guard last != group`)에 쓰이는 `lastRegisteredGroupsByID`를 건드리지 않으므로, 비우지 않으면 `last==group`이 남아 다음 foreground sync가 그룹을 스킵 → **자정 하트비트까지(~최대 24h) 재등록 불가**. 실패 그룹을 `last==nil`로 만들면 다음 sync가 즉시 재등록한다(하트비트 경로의 "성공 시에만 registered 기록" 계약과 동일, `DeviceActivityMonitorExtension/CLAUDE.md:29`).
- `reconnectMonitoring()`은 `DeviceActivityCenter.stopMonitoring()`으로 **override activity까지 전부 멈춘다**. 사용량 기반 override 메타데이터(`usageBasedOverrideGroupIDs`, baseline/grant, `overrideUntil`)를 보존하면 해당 그룹이 계속 Shield union에서 제외되어 재잠금 이벤트가 다시 올 수 없다. 재연결 전에는 `SharedStore.clearAllOverrideState()`로 override만 비우고, `shieldedGroupIDs`/usedTime은 보존해 현재 규칙 기준으로 즉시 재쉴드되게 한다.
- **Analytics 대기 큐(`pendingAnalyticsEvents`)**: extension은 Firebase를 링크하지 않으므로(메인 앱 전용 `Core/Analytics/AnalyticsService`), extension에서 발생한 이벤트는 `SharedStore.enqueueShieldHit`/`enqueueScreenTimeError`로 큐에 쌓고 메인 앱이 `AppLifecycleViewModel.appDidBecomeActive` → `drainPendingAnalyticsEvents()`에서 Firebase로 전송한다. `ScreenTimeManager`(Core)도 Firebase를 모르므로 override 등록 실패를 이 큐(`enqueueScreenTimeError`)로 보낸다. 페이로드는 `[String:String]`만 담는 plain Codable(`PendingAnalyticsEvent`)이라 extension 빌드에 Firebase 의존성을 들이지 않는다. 디코딩은 절대 throw하지 않고(실패 시 빈 배열), 상한 200건. **자정 리셋 대상 아님**(`clearAllShieldState`에 넣지 말 것 — 드레인 전 이벤트가 소실됨). 메인 앱 흐름 이벤트는 큐를 거치지 않고 `AnalyticsRepository`(Domain)로 직접 로깅한다.
- **자정 자율 재무장의 주 경로는 `DailyMonitor.dailyHeartbeat`**(`00:00~23:59:59, repeats:true, 이벤트 없음`)다. daily/cooldown 측정창(`freshDailyWindow`/`CooldownMonitor.usageSchedule`)은 date-less·`repeats:false`라 자정 재무장이 **undocumented**(코드·문서·1.0.0으로 단정 불가) — 여기 의존하지 말 것. **하트비트는 `DailyMonitor.needsHeartbeat`가 true(daily/cooldown 그룹 ≥1)일 때만 등록**한다. 시간대-only는 window가 `repeats:true`라 불필요하고, **시간대 그룹은 window 최대 3개 + 연장 `override`로 그룹당 최대 4개** activity를 써서 `maxGroupCount`(5) 전부 시간대면 4×5=20으로 DeviceActivity 동시 모니터링 상한에 닿는다 — 하트비트(+1)를 무조건 더하면 `excessiveActivities`로 넘칠 수 있어 조건부로 둔다. 시간대-only로 바뀌면 `stopMonitoring([.dailyHeartbeat])`로 멈춘다. 등록 실패는 핵심 경로이므로 **`try?`로 삼키지 말고 `firstError`로 전파**. 죽은 `dailySchedule`(repeats:true, 미등록)은 제거됨.
- **daily 등록 자산은 `DailyMonitor.swift`(앱·extension 공유)로 이동**: `DeviceActivityName.{daily,dailyGroup,dailyGroupID,dailyHeartbeat}`, `DeviceActivityEvent.Name.{tick,tickInfo}`, `freshDailyWindow`, `dailyThresholdMinutes`, `startUsageMonitoring`(옛 `registerGroup`), `policySnapshot` 어댑터, `isTrackable`. **같은 멤버를 `ScreenTimeManager`나 extension에 다시 선언하면 두 타겟에서 중복 선언이 된다.** `isTrackable`은 범위를 재작성하지 않고 `ScreenTimeGroupPolicy.invalidReason`를 재사용(드리프트 0) — 이 때문에 정책 3개(`ScreenTimeGroupPolicy/TimeWindowPolicy/CooldownPolicy`)+`Domain/Model/TimeWindow.swift`를 extension 멤버십에 추가했다.
