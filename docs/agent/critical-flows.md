# Critical Flows

Read when: Screen Time, Shield, 보상형 광고, App Group 공유 상태, extension 런타임 흐름을 바꿀 때.

Skip when: 독립 UI, 문구, 문서, 순수 테스트만 바꿀 때.

Screen Time, Shield, 보상형 광고, 공유 상태, extension 동작을 바꾸기 전에 읽습니다.

## Shared State 계약

`SharedStore`(`Core/Persistence/SharedStore.swift`)는 메인 앱과 extension이 함께 쓰는 App Group UserDefaults wrapper입니다.

- App Group suite: `group.com.goldtime.shared`
- 핵심 값:
  - 앱 그룹 목록과 그룹별 앱 token / 일일 제한 시간
  - 모니터링 활성 여부
  - 일일 1분 연장 사용 횟수
  - Shield 활성 상태와 잠긴 그룹 id
  - 그룹별 시간 연장 종료 시각
  - Shield에서 GoldTime으로 들어온 앱 token
  - 날짜별 통계
- key 이름이나 Codable 구조를 바꾸면 이미 설치된 앱의 저장 상태에 영향을 줄 수 있습니다.
- 메인 앱과 extension이 같은 값을 읽고 쓰므로, state 변경은 의도적인 migration/reset이 없는 한 하위 호환을 우선합니다.

## Daily Monitoring 흐름

1. 메인 앱이 FamilyControls 권한을 요청합니다.
2. 사용자가 앱 그룹을 만들고 각 그룹에 앱 또는 Safari 웹사이트와 일일 한도를 선택합니다. 카테고리는 앱으로 펼쳐 저장하고, 웹사이트는 Safari에서 사용하는 것만 지원합니다.
3. 그룹 저장, 앱 시작, active 복귀 시 `ScreenTimeManager.syncDailyMonitoring(groups:)`(`Core/ScreenTime/ScreenTimeManager.swift`)가 그룹 목록을 저장하고 유효한 그룹만 `.daily` 모니터링에 자동 적용합니다. 메인 앱에서는 `ScreenTimeRepositoryImpl` → `SyncProtectionUseCase`를 통해 호출됩니다.
4. 유효한 그룹은 앱 또는 웹사이트 1개 이상, 일일 한도 1분 이상, 앱+웹사이트 합산 그룹당 제한 이내인 그룹입니다. 설정이 덜 끝난 그룹은 저장하지만 `.daily` 이벤트에서는 제외합니다.
5. `.daily` activity 안에 `dailyLimit.<groupID>` 이벤트가 유효 그룹별로 등록됩니다.
6. `DeviceActivityMonitorExtension.eventDidReachThreshold`가 해당 그룹 id를 `SharedStore.shieldedGroupIDs`에 추가합니다.
7. Extension이 Shield hit을 기록하고 잠긴 그룹들의 앱 token union과 웹사이트 token union을 Shield로 적용합니다. override 중인 그룹은 union에서 제외합니다.
8. 메인 앱은 열릴 때나 active 상태가 될 때 공유 Shield 상태를 읽고 모니터링 등록을 다시 동기화합니다.
9. 같은 날짜의 foreground 자동 동기화와 `.daily` 재등록은 기존 `shieldedGroupIDs`를 지우면 안 됩니다. 잠금 상태 초기화는 실제 날짜가 바뀌었거나 전체 보호 초기화를 명시 실행했을 때만 허용합니다.

## 그룹 수정 자동 적용 흐름

1. 사용자가 그룹 이름, 앱 선택, 일일 한도, 그룹 삭제를 수정합니다.
2. 이름 변경은 그룹 저장만 수행하고 DeviceActivity를 재등록하지 않습니다.
3. 앱 선택, 한도 변경, 그룹 삭제는 `ScreenTimeManager.syncDailyMonitoring(groups:)`를 호출합니다.
4. sync는 전체 그룹을 `SharedStore.screenTimeGroups`에 저장하되, 유효 그룹만 DeviceActivity event로 등록합니다.
5. 삭제되었거나 무효화된 그룹 id는 `shieldedGroupIDs`와 override 상태에서 제거합니다.
6. 남아 있는 잠긴 그룹이 있으면 Shield union을 재계산하고, 없으면 Shield를 비웁니다.
7. 앱 시작/active 복귀 때문에 동일 설정을 재등록하는 경우에는 잠긴 유효 그룹을 보존해야 합니다.

## 전체 보호 초기화 흐름

1. 홈의 문제 해결 메뉴에서 `전체 보호 초기화`를 선택합니다.
2. confirmationDialog가 "모든 모니터링과 현재 잠금을 초기화합니다. 그룹 설정은 유지됩니다."를 표시합니다.
3. 확인하면 `ScreenTimeManager.resetProtectionState()`가 모든 DeviceActivity 모니터링과 ManagedSettings Shield를 정리하고 Shield/override 공유 상태를 비웁니다.
4. 같은 함수가 저장된 그룹을 다시 읽어 유효 그룹만 `.daily` 모니터링에 자동 적용합니다.
5. 이 기능은 사용자용 일시정지가 아니라 Screen Time 상태 꼬임, 개발 중 디버깅, stale Shield 복구를 위한 숨은 destructive action입니다.

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
4. `consumeAdReward`는 광고 통계를 기록하고 해당 그룹만 15분 동안 override 처리합니다.
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
