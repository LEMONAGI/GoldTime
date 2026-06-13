# Critical Flows

Read when: Screen Time, Shield, 보상형 광고, App Group 공유 상태, extension 런타임 흐름을 바꿀 때.

Skip when: 독립 UI, 문구, 문서, 순수 테스트만 바꿀 때.

Screen Time, Shield, 보상형 광고, 공유 상태, extension 동작을 바꾸기 전에 읽습니다.
이 문서는 여러 레이어를 가로지르는 **end-to-end 흐름**을 다룹니다. 특정 레이어/타겟에서만
걸리는 국소 함정은 그 폴더의 nested `CLAUDE.md`(`Core/`, `DeviceActivityMonitorExtension/`
등)에도 있고, 그 파일을 열면 자동 로드됩니다.

## Shared State 계약

`SharedStore`(`Core/Persistence/SharedStore.swift`)는 메인 앱과 extension이 함께 쓰는 App Group UserDefaults wrapper입니다.

- App Group suite: `group.com.goldtime.shared`
- 핵심 값:
  - 앱 그룹 목록과 그룹별 앱 token / 일일 제한 시간
  - 그룹별 차단 규칙 종류(`ruleKind`: 일일 한도 또는 시간대), 차단 시간대 목록(`timeWindows`), 적용 여부(`isApplied`)
  - 모니터링 활성 여부
  - 일일 1분 연장 사용 횟수
  - Shield 활성 상태와 잠긴 그룹 id
  - 그룹별 시간 연장 종료 시각
  - Shield에서 GoldTime으로 들어온 앱 token
  - 날짜별 통계
- key 이름이나 Codable 구조를 바꾸면 이미 설치된 앱의 저장 상태에 영향을 줄 수 있습니다.
- 메인 앱과 extension이 같은 값을 읽고 쓰므로, state 변경은 의도적인 migration/reset이 없는 한 하위 호환을 우선합니다.
- `ScreenTimeGroup`의 새 필드는 custom Codable로 절대 throw하지 않게 디코딩합니다. `screenTimeGroups` getter가 배열 전체를 `try?`로 디코딩하므로 그룹 1개의 실패가 전체 소실로 이어지기 때문입니다. 구버전 페이로드(`isApplied` 키 없음)는 "일일 한도 + 적용됨"으로 디코딩됩니다.

## Daily Monitoring 흐름

1. 메인 앱이 FamilyControls 권한을 요청합니다.
2. 사용자가 앱 그룹을 만들고 각 그룹에 앱 또는 Safari 웹사이트와 차단 규칙(일일 한도 또는 시간대별 차단)을 선택합니다. 카테고리는 앱으로 펼쳐 저장하고, 웹사이트는 Safari에서 사용하는 것만 지원합니다. 새 그룹은 draft(`isApplied=false`)로 시작하고, "적용하기"를 눌러야 모니터링이 시작됩니다. 적용 이후 규칙 변경·삭제·제한 항목 수정은 광고 게이트를 거칩니다(이름 변경 제외).
3. 그룹 저장, 앱 시작, active 복귀 시 `ScreenTimeManager.syncDailyMonitoring(groups:)`(`Core/ScreenTime/ScreenTimeManager.swift`)가 그룹 목록을 저장하고 유효한 그룹만 `.daily` 모니터링에 자동 적용합니다. 메인 앱에서는 `ScreenTimeRepositoryImpl` → `SyncProtectionUseCase`를 통해 호출됩니다.
4. 유효한 그룹은 적용됨(`isApplied`) + 앱 또는 웹사이트 1개 이상 + 규칙이 유효(일일 한도 0분 이상, 시간대는 TimeWindowPolicy 통과) + 앱+웹사이트 합산 그룹당 제한 이내인 그룹입니다. draft이거나 설정이 덜 끝난 그룹은 저장하지만 모니터링에서는 제외합니다.
5. 일일 한도 그룹은 `daily.<groupID>.<generation>` activity에 `tick.<groupID>.<minute>` 이벤트로, 시간대 그룹은 시간대당 `window.<groupID>.<index>` activity(이벤트 없음, repeats)로 등록됩니다.
6. `DeviceActivityMonitorExtension.eventDidReachThreshold`가 해당 그룹 id를 `SharedStore.shieldedGroupIDs`에 추가합니다.
7. Extension이 Shield hit을 기록하고 잠긴 그룹들의 앱 token union과 웹사이트 token union을 Shield로 적용합니다. override 중인 그룹은 union에서 제외합니다.
8. 메인 앱은 열릴 때나 active 상태가 될 때 공유 Shield 상태를 읽고 모니터링 등록을 다시 동기화합니다.
9. 같은 날짜의 foreground 자동 동기화와 `.daily` 재등록은 기존 `shieldedGroupIDs`를 지우면 안 됩니다. 잠금 상태 초기화는 실제 날짜가 바뀌었거나 전체 보호 초기화를 명시 실행했을 때만 허용합니다.

## 그룹 수정 자동 적용 흐름

1. 사용자가 그룹 이름, 앱 선택, 차단 규칙(일일 한도/시간대), 그룹 삭제를 수정합니다. 적용된 그룹은 이름 변경을 제외한 모든 수정 전에 광고 게이트를 거칩니다.
2. 이름 변경은 그룹 저장만 수행하고 DeviceActivity를 재등록하지 않습니다.
3. 앱 선택, 규칙 변경, 그룹 삭제, 그룹 적용은 `ScreenTimeManager.syncDailyMonitoring(groups:)`를 호출합니다.
4. sync는 전체 그룹을 `SharedStore.screenTimeGroups`에 저장하되, 유효 그룹만 DeviceActivity event로 등록합니다.
5. 삭제되었거나 무효화된 그룹 id는 `shieldedGroupIDs`와 override 상태에서 제거합니다.
6. 남아 있는 잠긴 그룹이 있으면 Shield union을 재계산하고, 없으면 Shield를 비웁니다.
7. 앱 시작/active 복귀 때문에 동일 설정을 재등록하는 경우에는 잠긴 유효 그룹을 보존해야 합니다.

## 시간대 차단 흐름

1. 시간대 그룹은 시간대마다 `window.<groupID>.<index>` activity가 `repeats: true`로 등록됩니다 (그룹당 최대 3개, 시간대는 15분 이상·자정 넘김 금지).
2. 잠김 판정은 이벤트가 아니라 "현재 시각이 시간대 안인지"라는 지속 조건입니다. `SharedStore.resyncTimeWindowLocks(now:)`가 이 판정을 `shieldedGroupIDs`에 반영하며, 일일 한도 그룹과 draft 그룹은 건드리지 않습니다.
3. resync는 모든 경계 지점에서 호출됩니다: `syncDailyMonitoring` 말미(적용/앱 복귀 시 즉시 판정), extension의 window `intervalDidStart`/`intervalDidEnd`, 일일 리셋 직후, override 종료 경로(연장 소진 재잠금 시 시간대가 끝난 그룹 오잠금 방지), `reapplyShieldIfOverrideExpired`(foreground 1초 보정).
4. 시간대 잠금도 기존 `shieldedGroupIDs`를 그대로 쓰므로 광고 10분/1분 연장 흐름이 수정 없이 동작합니다.
5. 모든 그룹이 시간대 규칙이면 `daily.*` activity가 없어 자정 콜백이 사라질 수 있습니다. window `intervalDidStart`의 일일 리셋 점검 + 자정 BGTask(`MonitoringBackgroundTask`) + 앱 active 동기화가 이를 보완합니다.

## 1분 연장 흐름

1. 사용자가 Shield 경로에서 GoldTime을 열고 1분 연장을 선택합니다.
2. `LockOptionsView`가 Shield에서 들어온 앱 token 또는 웹사이트 token으로 잠긴 후보 그룹을 찾고, 필요하면 사용자가 한 그룹을 고릅니다.
3. `LockOptionsView`가 `ScreenTimeManager.consumeOneMinute(for:)`를 호출합니다.
4. `ScreenTimeManager`가 필요하면 카운터를 리셋하고, `SharedStore.oneMinuteDailyLimit`을 확인한 뒤 사용 횟수와 통계를 기록하고 해당 그룹만 override 처리합니다.
5. `releaseShield(forSeconds:groupID:)`는 `override.<groupID>` 일회성 모니터링을 시작하고, 다른 잠긴 그룹은 Shield union에 유지합니다.
6. `DeviceActivityMonitorExtension.intervalDidEnd`가 해당 그룹 override를 비우고 Shield union을 다시 적용합니다.

## 광고 해제 흐름

1. `RewardedAdService`가 AdMob rewarded ad를 로드합니다.
2. `AdMockView`가 광고 준비 상태를 보고 광고를 표시합니다.
3. 보상 콜백이 성공하면 앱이 선택된 그룹 id로 `ScreenTimeManager.consumeAdReward(for:)`를 호출합니다.
4. `consumeAdReward`는 광고 통계를 기록하고 해당 그룹만 10분 동안 override 처리합니다.
5. `override.<groupID>` 모니터링 종료 시점에 해당 그룹이 다시 Shield union에 포함되어야 합니다.

## Shield 복귀 흐름

1. ManagedSettings가 시스템 Shield를 표시합니다.
2. `ShieldConfigurationExtension`이 Shield UI 문구와 버튼을 구성합니다.
3. `ShieldActionExtension`이 버튼 탭을 처리합니다.
4. Extension에서는 앱을 직접 열 수 없으므로, "GoldTime 가기" 경로는 open request와 앱 token을 기록하고 로컬 알림을 예약합니다.
5. 메인 앱은 open request를 비우고 필요한 경우 `LockOptionsView`를 보여줍니다. `LockOptionsView`는 앱 token 또는 웹사이트 token이 속한 잠긴 그룹을 연장 후보로 표시합니다.

## 일일 리셋 흐름

- Daily DeviceActivity interval 경계에서 1분 연장 카운터와 Shield 상태를 정리합니다.
- `ScreenTimeManager.rolloverCounterIfNeeded()`도 앱이 active가 될 때 카운터를 보정합니다.
- 통계는 현재 calendar 기준 date key를 쓰므로 날짜 로직 변경에 주의합니다.

## 실기기 제약

FamilyControls, DeviceActivity callback, ManagedSettings Shield, Shield extension은 실기기 검증이 필요합니다. 시뮬레이터 build는 유용하지만 런타임 동작을 증명하지 않습니다.
