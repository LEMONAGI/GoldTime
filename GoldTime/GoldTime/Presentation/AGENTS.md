# Presentation 레이어

ViewModel + View (MVVM). 화면별 폴더 + 공용 `Component/`. 구성요소는 폴더를 직접 보면 된다.

## ViewModel 패턴 (코드만 봐선 모르는 것)

- `@MainActor @Observable final class XxxViewModel`.
  단 `HomeViewModel`·`StatsViewModel`처럼 계산만 하는 VM은 **순수 struct 허용**.
- DI: UseCase를 생성자에서 `XxxUseCase? = nil`로 받음. nil이면 내부에서 `RepositoryImpl`을
  생성해 UseCase에 주입하여 기본 구현을 만든다.
- **Core 서비스(`ScreenTimeManager`, `AuthorizationService`) 직접 참조 금지** — UseCase만 의존.
- import은 `Foundation`만. `import FamilyControls`는 `AppPickerSheet` 등 FamilyActivityPicker를
  직접 쓰는 화면에서만, `import ManagedSettings`는 `LockOptionsViewModel`의 그룹 토큰 타입
  참조에서만 예외.
- View는 `@Bindable var viewModel: XxxViewModel`(소유는 GoldTimeApp 또는 상위 View).

## 기술 부채 (의도된 예외 — 향후 이동 예정)

- `SharedStore.weekStartDay`를 `SettingsViewModel`·`AppLifecycleViewModel`에서 직접 읽기/쓰기.
- `SharedStore.suiteName`을 `ContentView`의 `@AppStorage` store로 사용.
- `SharedStore.max*` 상수를 `AppPickerSheetViewModel`·`LockOptionsViewModel`에서 직접 참조.

## UI / 컴포넌트 / 색상

- 기본 iOS 컴포넌트 우선. 날짜/시간·선택·설정·확인은 `DatePicker`/`Picker`/`Form`/
  `confirmationDialog`를 먼저 검토하고, 대체 커스텀 UI는 이유를 남긴다. HIG/iOS 26.0 적합성 확인.
- 공용 컴포넌트는 `Presentation/Component/`(현재 10개: CardContainerModifier,
  CountUpDurationText, DashboardMetricCard, GoldTimeButtonStyle, GoldTimeFormatters, IconTile,
  SectionHeader, SegmentedProgressBar, StatusBadge, StreakCard). 2곳 이상 반복되면 추출 검토.
- 색상: 새 색은 RGB/hex literal 금지, Asset Color로 추가해 이름으로 사용. `AccentColor`는
  `Color.accent`(Xcode 자동 생성, extension 불필요 — `Color+Brand.swift` 만들면 `invalid
  redeclaration`). 자세히는 `docs/agent/ui-design-system.md`.

톤·문구 판단은 `docs/agent/product-context.md`.

## 주의사항 (작업 중 발견 시 누적)

- (작업 중 발견한 Presentation 함정을 한 줄씩 누적)
