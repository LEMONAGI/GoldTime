# App 레이어

진입점 + DI 조립만. 구성요소는 이 폴더를 직접 보면 된다.

- 책임: `GoldTimeApp`(앱 진입), `AppDIContainer`(모든 레이어 조립).
- DI 조립 외 **비즈니스 로직 없음**.

## 코드만 봐선 모르는 것

- `AppDIContainer`는 `@MainActor final class`. Repository는 `private lazy var`,
  UseCase/ViewModel은 팩토리 메서드(`makeXxxUseCase()`, `makeContentViewModel()`).
- `AppDIContainer`는 `GoldTimeApp.init()`에서 **지역 변수로 생성 후 해제돼도 무방**하다.
  ViewModel이 UseCase를, UseCase가 Repository를 ARC로 유지한다.
- `GoldTimeApp`은 ViewModel을 `@State`로 소유하고 `ContentView`에 `@Bindable`/`let`으로 전달.
- 새 기능 배선 순서: Repository(Domain protocol) → UseCase 주입 → AppDIContainer에
  lazy var + 팩토리 추가 → Presentation 생성자에 주입. 자세히는 `docs/agent/architecture.md`.

## Firebase / Analytics (코드만 봐선 모르는 것)

- `GoldTimeApp.init()`에서 `AnalyticsService.shared.configure()`로 **FirebaseApp을 1회 구성**한다
  (모든 Analytics 호출보다 먼저). `GoogleService-Info.plist`는 동기화 폴더로 메인 앱에 자동 포함.
- **`AppDIContainer`는 현재 미사용(dead code)** — ViewModel은 `GoldTimeApp`/각 View에서 no-arg
  init으로 직접 생성되고, 실제 DI는 ViewModel 생성자의 `? = nil` 기본값(nil이면 내부에서
  `XxxRepositoryImpl()` 생성)으로 이뤄진다. 그래서 `analyticsRepository`도 ViewModel 생성자에
  `(any AnalyticsRepository)? = nil`로 주입하면 기존 테스트를 깨지 않는다(컨테이너 팩토리는
  일관성용으로만 함께 갱신).
- 메인 앱 흐름 이벤트는 ViewModel에서 `AnalyticsRepository`로 직접 로깅. extension 발생
  이벤트는 `SharedStore` 큐 경유(Core/CLAUDE.md "Analytics 대기 큐" 참조).
- 규칙 분석은 **익명 전체 집계만** 남긴다. `group_applied`와 `rule_monitoring_registered`는
  `rule_kind`/설정값 bucket만 보내고, 사용자별 그룹 이름·선택 앱/웹사이트·UUID는 보내지 않는다.
  `rule_monitoring_registered`는 사용자가 적용/편집한 그룹이 sync 후 유효 모니터링 대상일 때만
  남기며, foreground/lifecycle 재동기화는 사용 집계에서 제외한다.
- **Crashlytics는 메인 앱만**. extension 타겟에 Firebase를 링크하지 말 것(바이너리/메모리).
