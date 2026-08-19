# App 레이어

진입점만. 구성요소는 이 폴더를 직접 보면 된다.

- 책임: `GoldTimeApp`(앱 진입, 루트 ViewModel 소유, scene phase 처리).
- 비즈니스 로직 없음.

## DI 패턴 (코드만 봐선 모르는 것)

- **공식 DI는 ViewModel 생성자 기본값 주입이다** — 중앙 DI 컨테이너 없음. 과거
  `AppDIContainer`는 실사용 없는 이중 경로(dead code)라 2026-07 삭제했다(재도입하지 않는다,
  ADR: `docs/agent/decision-context.md`).
- ViewModel 생성자는 UseCase/Repository를 `XxxUseCase? = nil`로 받고, nil이면 내부에서
  `XxxRepositoryImpl()`을 생성해 조립한다. 프로덕션은 no-arg 생성(`ContentViewModel()`),
  테스트는 Fake를 명시 주입(`GoldTimeTests/ViewModelTests.swift` 참조).
- `GoldTimeApp`은 루트 ViewModel(AppLifecycle/Content/Settings)을 `@State`로 소유하고
  `ContentView`에 `@Bindable`/`let`으로 전달. 화면 지역 ViewModel(LockOptions/RewardedAd/
  Onboarding/Stats 등)은 해당 View가 `@State`로 직접 생성한다.
- 새 기능 배선 순서: Repository protocol(Domain) → Impl(Data) → UseCase 주입 →
  ViewModel 생성자에 `? = nil` 파라미터 추가(기본 조립 경로 유지 — 기존 no-arg 호출부와
  테스트를 깨지 않는다). 자세히는 `docs/agent/architecture.md`.

## Firebase / Analytics (코드만 봐선 모르는 것)

- `GoldTimeApp.init()`에서 `AnalyticsService.shared.configure()`로 **FirebaseApp을 1회 구성**한다
  (모든 Analytics 호출보다 먼저). `GoogleService-Info.plist`는 동기화 폴더로 메인 앱에 자동 포함.
- 메인 앱 흐름 이벤트는 ViewModel에서 `AnalyticsRepository`로 직접 로깅. extension 발생
  이벤트는 `SharedStore` 큐 경유(Core/CLAUDE.md "Analytics 대기 큐" 참조).
- 그룹 분석은 **익명 전체 집계만** 남긴다. 앱 활성화에서 `group_snapshot`으로
  적용 그룹 수 버킷(0도 포함), 행동은 `group_applied`/`group_deleted`만 보낸다.
  그룹 이름·선택 앱/웹사이트·UUID는 보내지 않고, 모니터링 등록·동기화 성공은
  제품 행동 이벤트로 수집하지 않는다.
- 사용자 속성은 현재 적용 상태를 표현한다. `active_rule_profile`/`strict_rule_profile` 값은
  `wdN_dlN_twN_cdN`(요일별/일일 한도/시간대/쿨다운의 **top-level 그룹 수**)이고, strict는
  아직 만료되지 않은 연장 불가 그룹만 센다. 그룹명·UUID·선택 앱·요일 조합은 보내지 않는다.
  설정 변경 후와 앱 활성화 시 모두 갱신하므로, `strict_lock_started`/
  `strict_lock_extended` 등 다음 이벤트를 현재 구성과 조인할 수 있다.
- 권한 사용자 속성 `authorized_screen_time`/`authorized_notification`은
  `scenePhase == .active`에서 await하여 매번 최신화한다. 이 작업이 끝난 뒤 진입 시
  Screen Time 권한 요청을 시작해, 최소한 활성화 순간의 상태를 먼저 기록한다.
- 앱 활성화 시 적용 그룹마다 `rule_uniform_daily`/`rule_uniform_time_window`/
  `rule_uniform_cooldown`/`rule_weekday_snapshot` 중 하나를 보낸다. 요일별 내부 규칙은
  `weekday_*_days`, 연장 불가는 독립 파라미터 `strict_lock_active`로 기록한다.
- `GoldTimeApp`의 LockOptions sheet 두 진입점은 분석 출처를 명시해야 한다. Shield 복귀는
  `entrySource: .shield`, 홈 그룹 카드는 `.homeGroup`으로 전달해
  `shield_extend_options_viewed.entry_source`가 섞이지 않게 한다.
- 광고 연장 분석도 수익 추정/실제 paid revenue 없이
  `shield_extend_completed(extend_method=ad)` 횟수와 익명 규칙 snapshot만 남긴다.
  `estimatedWonPerAd`·`estimatedAdRevenueWon`은 분석 이벤트에서 참조하지 않는다.
- **Crashlytics는 메인 앱만**. extension 타겟에 Firebase를 링크하지 말 것(바이너리/메모리).
