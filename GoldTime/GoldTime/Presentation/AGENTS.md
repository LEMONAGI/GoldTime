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
- `ConsentService.shared`(Core/Ads)를 `OnboardingViewModel`·`SettingsViewModel`에서 직접 참조
  (UMP 동의/철회). UseCase 미경유 — UMP 폼 표시는 부수효과만이라 UseCase가 과해서 둔 예외.

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
- **로컬라이징은 semantic key 방식**(키 = `domain.screen.element` dot-notation, 값 = `Localizable.xcstrings`의 ko). 코드에 한국어 리터럴을 직접 쓰지 말고 키만 쓴다. 두 갈래: View의 `Text`/`Button`/`Label`/`.navigationTitle`/`Picker`/`DatePicker`/`.confirmationDialog`는 `LocalizedStringKey`를 자동으로 받으니 `Text("home.title")`처럼 키만, ViewModel 계산 속성·동적 메시지·`ShieldConfiguration.Label`은 `String(localized: "key")`. 보간은 `"key \(value)"` → 카탈로그 키가 `"key %lld"`(Int)·`"key %@"`(String), 값은 위치 지정자 `%1$@ %2$lld`. 키 추가는 코드 전환 후 `python3`로 `Localizable.xcstrings`에 병합(`extractionState:"manual"`, ko `state:"translated"`).
- **재사용 컴포넌트의 텍스트 파라미터는 반드시 `LocalizedStringKey`로 받는다**(`SectionHeader.title`, `OnboardingStepView.title`, `RuleEditorSheet.ruleRow`, `NotificationSettingsView.toggleRow` 등). `String`으로 받으면 내부 `Text(param)`이 **verbatim**이라 키 문자열(`"settings.title"`)이 화면에 그대로 노출된다 — 컴파일은 통과해 시뮬/실기기로만 잡힌다. 예외: 파라미터 값이 이미 `String(localized:)`로 번역된 동적 문자열이거나(`DashboardMetricCard.title/value`처럼) `subtitle`이 ViewModel computed `String?`이면 `String`으로 받고 호출부에서 `String(localized:)`로 만든다. `Text(someStringVar)`는 항상 verbatim임을 기억.
- enum의 `rawValue`를 화면에 직접 쓰면(`Text(mode.rawValue)`) 로컬라이징 안 된다 → `var title: LocalizedStringKey` 같은 별도 프로퍼티로 분리(`Text(mode.title)`). 이모지·숫자식별자는 `Text(verbatim:)`로 키 추출/조회를 피한다.
- **통계 카드의 추세(화살표·색)·delta 문구는 반드시 표시값과 같은 올림 분 단위로 비교한다**(`StatsViewModel.displayTrend`/`displayMinutes`, `todayDeltaCaption`/`weeklyDeltaCaption`). 카드 값은 `goldTimeDurationText`가 **올림 분**으로 보여주므로, 추세를 초 단위 delta나 합계로 판단하면 표시값과 어긋난다 — `14분인데 ↑빨강`(합계 비교 회귀), `둘 다 15분인데 "1분 적어요"`(초 단위 비교) 같은 버그. 하단 기록 섹션(`StatsComparison`)도 같은 `displayMinutes` 분 단위 비교를 쓴다. Domain `StatsReport`는 raw 초 단위 평균만 노출하고(`weeklyAverageSeconds` 등) **추세 판단은 ViewModel이 분 단위로** 한다 — `StatsReport`에 trend/합계 delta를 도로 넣지 말 것. 표시값-화살표 일치는 단위 테스트로 잡히지만(`statsViewModelWeeklyTrend*`) 실기기 색·방향은 시뮬/실기기로만 확인.
- **요일 편집 UX의 '제한 없음'은 두 갈래다(`RuleEditorSheet`)**: implicit(토글 시드·묶음에서 요일 해제, `isExplicitlyUnrestricted == false`)은 묶음 행을 만들지 않고 스트립 회색 대시로만 보이고, explicit(편집 화면에서 '제한 없음'을 직접 골라 저장)만 행이 된다(`visibleBundles`). 스트립에서 implicit 요일 탭 = 그 하루만 선택 + '제한 없음' 선택 상태로 진입(`tapEditTarget`), **무변경 완료도 explicit 승격 → 행 생성(의도된 동작 — '완료' = 직접 설정)**. 신규(draft) 그룹 토글 ON은 implicit 7개 시드(`seededWeekdayRules`, 행 0개 시작), 기존 규칙 그룹은 base 규칙 × 7 시드. 단 **같은 시트 세션에서 토글 OFF→ON은 재시드가 아니라 보관본 복원**(`stashedWeekdayRules` @State — OFF 때 편집 내용을 보관, 시트가 닫히면 소멸). `allUnrestricted` 무효 상태의 footer는 빨간 에러가 아니라 중립 안내(`rule.weekday.empty.footer`)이며 완료 disabled는 유지 — 이 분기를 없애고 에러로 통일하지 말 것(빈 시작 상태가 곧바로 빨간 에러로 보인다).
