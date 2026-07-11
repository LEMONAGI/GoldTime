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
- 규칙 분석은 **익명 전체 집계만** 남긴다. `group_applied`와 `rule_monitoring_registered`는
  `rule_kind`/설정값 bucket만 보내고, 사용자별 그룹 이름·선택 앱/웹사이트·UUID는 보내지 않는다.
  `rule_monitoring_registered`는 사용자가 적용/편집한 그룹이 sync 후 유효 모니터링 대상일 때만
  남기며, foreground/lifecycle 재동기화는 사용 집계에서 제외한다.
- 광고 연장 분석도 수익 추정/실제 paid revenue 없이 `ad_unlock` 횟수와 익명 rule bucket만
  남긴다. `estimatedWonPerAd`·`estimatedAdRevenueWon`은 분석 이벤트에서 참조하지 않는다.
- **Crashlytics는 메인 앱만**. extension 타겟에 Firebase를 링크하지 말 것(바이너리/메모리).
