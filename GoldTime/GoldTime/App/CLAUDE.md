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
