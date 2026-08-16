# ShieldActionExtension — 위험도 High / 직렬

Shield 화면 버튼 액션을 처리하고 앱 복귀 요청을 기록한다.

## 코드만 봐선 모르는 것

- Extension에서는 **앱을 직접 열 수 없다**. "GoldTime 가기"는 `SharedStore`에 open request와
  대상 앱/웹사이트 token을 기록하고 **로컬 알림을 예약**하는 방식이다.
- 메인 앱이 열릴 때 open request를 비우고 필요하면 `LockOptionsView`를 띄운다(token이 속한
  잠긴 그룹을 연장 후보로 표시).
- App Group key·Codable 하위 호환 유지.

전체 흐름은 `docs/agent/critical-flows.md`의 "Shield 복귀 흐름". 실기기 검증 필수.

## 주의사항 (작업 중 발견 시 누적)

- **분석 이벤트는 `SharedStore`가 아니라 자체 `PendingAnalyticsStore`로 적재한다.** 이 타겟에는
  `SharedStore.swift`가 멤버가 아니다(동기화 폴더 멤버십 예외상 메인 앱·DeviceActivityMonitor
  타겟에만 추가됨, `project.pbxproj`). SharedStore를 이 타겟에 넣으면 `ScreenTimeGroup`·
  `TimeWindow`·policies·`DailyMonitor`·`CooldownMonitor`·`NotificationService`·`GTLogger`가
  줄줄이 딸려오므로(메인 폴더 파일들), `OpenRequestStore`/`DailyStatsStore`와 같은 자체 복제
  패턴을 쓴다 — App Group 키 `pendingAnalyticsEvents` + `SharedStore.PendingAnalyticsEvent`와
  **동일한 Codable 형태(`name`/`parameters: [String:String]`/`timestamp`)**. 형태가 어긋나면
  메인 앱 `drainPendingAnalyticsEvents()`가 디코딩 실패로 큐 전체를 잃는다.
  `primaryButtonPressed`→`shield_action_stop_selected`(차단 수용), `secondaryButtonPressed`→
  `shield_action_extend_selected`(연장 입구).
- **`shield_action_stop_selected`는 구조적 과소집계 편향이 있다.** '그만 쓰기'는 앱을 열지 않으므로 큐가
  다음 앱 재진입 때까지 드레인되지 않고, 재진입을 영영 안 하면 상한 200건 내에서 유실될 수
  있다. 대시보드 해석 시 로컬 `DailyStatsStore.walkAwayCount`(같은 액션에서 기록)로 교차검증.
