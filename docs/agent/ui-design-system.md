# UI Design System

Read when: SwiftUI UI 구현, 공용 컴포넌트 추출, 색상/Asset, HIG/iOS 26.0 UI 판단이 필요할 때.

Skip when: 순수 로직, 테스트, Screen Time 런타임, 광고 로딩, project config만 바꿀 때.

이 문서는 GoldTime UI가 기본 iOS 컴포넌트를 기반으로 HIG와 iOS 26.0 UI/UX에 자연스럽게 맞도록 만드는 기준입니다.

## 기본 원칙

"기본 iOS 컴포넌트를 쓰라"는 말은 순정 UI만 쓰라는 뜻이 아닙니다. 사용자가 iOS에서 기대하는 입력, 선택, 탐색, 피드백 패턴을 먼저 존중하라는 뜻입니다.

커스텀 UI를 만들기 전에 먼저 확인합니다.

- 이 입력이나 선택에 맞는 SwiftUI/iOS 기본 컴포넌트가 있는가.
- 기본 컴포넌트를 쓰면 HIG, 접근성, Dynamic Type, iOS 26.0 시각 언어에 더 자연스럽게 맞는가.
- 커스텀 UI가 GoldTime의 비용감, Shield 선택 경험, 반복 사용성을 실제로 개선하는가.
- 기본 컴포넌트를 피하는 이유를 코드 리뷰에서 설명할 수 있는가.

## 시스템 컴포넌트 우선 예시

- 날짜/시간 입력은 `DatePicker`를 먼저 검토합니다.
- 단일 선택은 `Picker`, `Menu`, `segmented` picker, `List`, `Form` 중 의미에 맞는 컨트롤을 먼저 검토합니다.
- 숫자 조정은 `Stepper`, `Slider`, `TextField`와 적절한 keyboard/content type을 먼저 검토합니다.
- 설정 화면은 `Form`, `List`, `Section`을 먼저 검토합니다.
- 화면 이동은 `NavigationStack`, `NavigationLink`, `sheet`, `fullScreenCover`를 먼저 검토합니다.
- 위험하거나 되돌리기 어려운 선택은 `confirmationDialog`나 `alert`를 먼저 검토합니다.
- 명령 버튼과 상태 아이콘은 SF Symbols와 시스템 `Button` 스타일을 먼저 검토합니다.
- Screen Time 대상 선택은 가능한 경우 Apple이 제공하는 picker와 framework 흐름을 우선합니다.

피해야 할 구현:

- 날짜를 버튼 30개로 직접 만드는 UI.
- 시간 설정에 `DatePicker`가 맞는데 시/분 `Picker` 두 개로 억지 구현하는 UI.
- 시스템 `Picker`, `Menu`, `Form`이 맞는 상황에서 탭 가능한 카드 묶음만으로 선택하게 만드는 UI.
- 버튼처럼 보여야 하는 행동을 텍스트, 카드, 장식 안에 숨기는 UI.
- HIG에서 익숙한 흐름을 벗어난 제스처나 컨트롤을 차별화처럼 포장하는 UI.

예외적으로 Shield, Lock Options, Dashboard의 핵심 상태 표현처럼 GoldTime의 선택 비용을 더 선명하게 만드는 곳은 커스텀 UI를 쓸 수 있습니다. 그래도 hit target, VoiceOver label, Dynamic Type, 색 대비, reduce motion을 확인합니다.

Apple 기준 문서:

- Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines/
- SwiftUI Documentation: https://developer.apple.com/documentation/swiftui/
- iOS/iPadOS 26 Release Notes: https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes

## 공용 컴포넌트

공용으로 쓰일 수 있는 UI는 `GoldTime/GoldTime/Views/Component/`에 둡니다.

폴더가 아직 없으면 공용 컴포넌트를 처음 추가하는 작업에서 생성합니다.

컴포넌트화 기준:

- 2곳 이상에서 쓰입니다.
- 지금은 1곳이지만 같은 형태가 반복될 가능성이 높습니다.
- 상태, 접근성, 스타일 규칙을 한 곳에서 유지하는 편이 낫습니다.
- 화면 파일의 private subview가 너무 커져 핵심 흐름을 읽기 어렵게 만듭니다.

해당 View 파일 안에 남겨도 되는 경우:

- 특정 화면의 맥락에 강하게 묶여 있습니다.
- 재사용 가능성이 낮습니다.
- 분리하면 props가 과하게 늘어 오히려 읽기 어렵습니다.

공용 컴포넌트 후보:

- metric card.
- section header.
- action button style.
- status badge.
- empty state.
- icon tile.

공용 컴포넌트는 GoldTime의 농담보다 iOS 사용성, 상태 표현, 재사용성을 우선합니다.

## Asset Color

새 색은 RGB literal이나 hex helper로 직접 쓰지 않습니다. `GoldTime/GoldTime/Assets.xcassets`에 Color Set으로 추가하고 이름으로 사용합니다.

예외:

- `AccentColor`는 Xcode가 `Color.accent`로 자동 생성하므로 extension 없이 `Color.accent`를 직접 씁니다. `Color.accentColor`는 deprecated이고 UIKit tint를 읽어 컨텍스트에 따라 금색이 아닌 파란색으로 렌더링될 수 있습니다.
- `.primary`, `.secondary`, `.red`, `Color(.systemGroupedBackground)`, `Color(.secondarySystemGroupedBackground)` 같은 Apple semantic color는 직접 사용해도 됩니다.

컬러 네이밍:

- 형식은 `색상명 + 숫자`입니다.
- 예: `gray50`, `gray70`, `gray100`, `gray150`, `gray200`, `gray350`, `blue100`, `gold100`.
- `100`을 기준 색으로 봅니다.
- 숫자가 작을수록 더 연하고, 클수록 더 진합니다.
- 같은 색상군 안에서만 숫자 의미를 비교합니다. `gray100`과 `blue100`이 같은 밝기일 필요는 없습니다.

초기 토큰 후보:

- `gold100`: 기존 GoldTime primary gold 계열.
- `gray100`: 기본 어두운 배경 계열.
- 실제 RGB 값은 문서나 Swift helper가 아니라 Asset Color 안에 둡니다.

사용 방식:

- `AccentColor`: `Color.accent` (Xcode 자동 생성 심볼, extension 불필요).
- 그 외 Asset Color: `Color("gray100")` 같은 문자열 참조.
- UIKit: `UIColor(named: "gray100")`.
- 수동 extension(`Color+Brand.swift` 등)으로 같은 이름의 심볼을 만들면 `invalid redeclaration` 에러 발생 — 만들지 않습니다.

기존 RGB literal을 만났을 때:

- 관련 작업 범위 안의 색이면 Asset Color로 옮깁니다.
- 범위 밖의 색이면 임의로 넓게 리팩터링하지 말고 남은 개선 항목으로 기록합니다.

## UI 검토 체크리스트

UI 작업 전후로 확인합니다.

- 이 입력/선택/탐색에 맞는 기본 iOS 컴포넌트를 먼저 검토했는가.
- HIG와 iOS 26.0 UI/UX에서 어색한 커스텀 컨트롤이 없는가.
- 공용 가능성이 있는 UI를 `Views/Component/`로 추출할지 판단했는가.
- 새 색상을 Asset Color로 추가했는가.
- Dynamic Type, VoiceOver, hit target, 색 대비가 깨지지 않는가.
- GoldTime다운 톤이 선택의 명료함을 가리지 않는가.
