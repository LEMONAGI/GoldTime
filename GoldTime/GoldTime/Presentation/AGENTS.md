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

- **자정 직전 안내는 경계가 둘이고 서로 다르다(헷갈리기 쉬움)**. 편집 중 RuleEditor 안 인라인
  notice(`ContentViewModel.nearMidnightEditNotice` / `isNearMidnightEditNoticeWindow`)는 **23:30**부터
  예고용으로 뜨고, 규칙 적용·수정 **직후** alert(`nearMidnightApplyNotice` / UseCase
  `isNearMidnightMonitorTooShort`)은 실제 모니터 등록이 `intervalTooShort`로 막히는 **23:45**부터만
  뜬다(Core의 `overrideWindowTooShort` 경유). alert은 **일일 한도·쿨다운만** — 시간대 차단은
  측정창과 무관해 제외(`commitTimeWindowsRule`은 안 건드림). 적용하기(`confirmApplyGroup`) 경로의
  alert은 확인 다이얼로그가 닫히는 사이클과 겹쳐 누락되지 않도록 `Task { @MainActor }`로 미뤄 띄운다.
- **[해결 불가 / API 한계] FamilyControls `Label(token)` 아이콘 크기**: 시스템이 렌더하는 뷰라
  `.frame`·`.font`은 무시되고 `.scaleEffect`만 먹힌다(확대 시 흐려짐). 게다가 기본 렌더 크기·여백이
  **토큰 종류(앱/웹)·기기·OS마다 제각각**이다(애플 포럼 thread 721432: iPhone 14 Pro ~20px+여백,
  XS/iPad ~40px+여백없음 / thread 731387: 애플도 미해결, Feedback Assistant 권장). 시도해 본 우회책
  모두 다른 문제를 유발 → 고정 `scaleEffect` 값은 OS별로 잘림/축소, GeometryReader 동적 측정은
  앱/웹 시각 크기 불일치, `fillScale` 여백 보정은 기기마다 깨짐. **완벽한 크기 통일은 불가능**으로
  결론. GroupCardView·LockOptionsView 모두 각자 `tokenIcon(_:)` 헬퍼로 OS별 라벨 체인을 통째로
  분기한다: iOS 26+는 `scaleEffect+frame+clip`(기본이 작아 키움), iOS 26 미만은 쌩 라벨 +
  `padding`(기본이 커서 키우면 잘리므로 간격만). 크기만 화면별로 다르다(GroupCard 28, LockOptions는
  작은 요약이라 20). 애플이 토큰 아이콘 크기 제어 API를 제공하기 전까지 더 손대지 말 것.
- Screen Time 복구 full-screen cover는 `AuthorizationCenter` 상태를 refresh하는 중의 transient
  `false`에 반응하면 깜빡인다. 초기 체크·observer 초기 콜백·`loadState()` refresh는 상태만 갱신하고,
  복구 UI는 홈 진입 후 재확인/권한 요청까지 실패해 미승인이 확정된 경로에서만 띄운다.
