# Critical Flows

Read when: Screen Time, Shield, 보상형 광고, App Group 공유 상태, extension 런타임 흐름을 바꿀 때.

Skip when: 독립 UI, 문구, 문서, 순수 테스트만 바꿀 때.

Screen Time, Shield, 보상형 광고, 공유 상태, extension 동작을 바꾸기 전에 읽습니다.

## Shared State 계약

`SharedStore`는 메인 앱과 extension이 함께 쓰는 App Group UserDefaults wrapper입니다.

- App Group suite: `group.com.goldtime.shared`
- 핵심 값:
  - 선택된 앱/카테고리/웹 도메인 token
  - 일일 제한 시간
  - 모니터링 활성 여부
  - 일일 1분 연장 사용 횟수
  - Shield 활성 상태
  - 시간 연장 종료 시각
  - 날짜별 통계
- key 이름이나 Codable 구조를 바꾸면 이미 설치된 앱의 저장 상태에 영향을 줄 수 있습니다.
- 메인 앱과 extension이 같은 값을 읽고 쓰므로, state 변경은 의도적인 migration/reset이 없는 한 하위 호환을 우선합니다.

## Daily Monitoring 흐름

1. 메인 앱이 FamilyControls 권한을 요청합니다.
2. 사용자가 앱/카테고리/도메인과 일일 한도를 선택합니다.
3. `ScreenTimeManager.startDailyMonitoring(limitMinutes:selection:)`가 선택값을 저장하고 `.daily` 모니터링을 시작합니다.
4. `DeviceActivityMonitorExtension.eventDidReachThreshold`가 `.dailyLimit` 이벤트를 받습니다.
5. Extension이 Shield hit을 기록하고 `SharedStore.selectedApps` 기준으로 Shield를 적용합니다.
6. 메인 앱은 열릴 때나 active 상태가 될 때 공유 Shield 상태를 읽습니다.

## 1분 연장 흐름

1. 사용자가 Shield 경로에서 GoldTime을 열고 1분 연장을 선택합니다.
2. `LockOptionsView`가 `ScreenTimeManager.consumeOneMinute()`를 호출합니다.
3. `ScreenTimeManager`가 필요하면 카운터를 리셋하고, `SharedStore.oneMinuteDailyLimit`을 확인한 뒤 사용 횟수와 통계를 기록하고 `releaseShield(forSeconds: 60)`을 호출합니다.
4. `releaseShield`는 Shield를 해제하고 일회성 `.override` 모니터링을 시작합니다.
5. `DeviceActivityMonitorExtension.intervalDidEnd(for: .override)`가 Shield를 다시 적용하고 `shieldOverrideUntil`을 비웁니다.

## 광고 해제 흐름

1. `RewardedAdService`가 AdMob rewarded ad를 로드합니다.
2. `AdMockView`가 광고 준비 상태를 보고 광고를 표시합니다.
3. 보상 콜백이 성공하면 앱이 `ScreenTimeManager.consumeAdReward()`를 호출합니다.
4. `consumeAdReward`는 광고 통계를 기록하고 15분 동안 Shield를 해제합니다.
5. `.override` 모니터링 종료 시점에 Shield가 다시 적용되어야 합니다.

## Shield 복귀 흐름

1. ManagedSettings가 시스템 Shield를 표시합니다.
2. `ShieldConfigurationExtension`이 Shield UI 문구와 버튼을 구성합니다.
3. `ShieldActionExtension`이 버튼 탭을 처리합니다.
4. Extension에서는 앱을 직접 열 수 없으므로, "GoldTime 가기" 경로는 open request를 기록하고 로컬 알림을 예약합니다.
5. 메인 앱은 open request를 비우고 필요한 경우 `LockOptionsView`를 보여줍니다.

## 일일 리셋 흐름

- Daily DeviceActivity interval 경계에서 1분 연장 카운터와 Shield 상태를 정리합니다.
- `ScreenTimeManager.rolloverCounterIfNeeded()`도 앱이 active가 될 때 카운터를 보정합니다.
- 통계는 현재 calendar 기준 date key를 쓰므로 날짜 로직 변경에 주의합니다.

## 실기기 제약

FamilyControls, DeviceActivity callback, ManagedSettings Shield, Shield extension은 실기기 검증이 필요합니다. 시뮬레이터 build는 유용하지만 런타임 동작을 증명하지 않습니다.
