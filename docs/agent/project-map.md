# Project Map

Read when: 수정할 코드 위치, target, 시작 파일이 불명확할 때.

Skip when: 수정 대상 파일을 이미 알고 있거나 제품/검증 판단만 필요할 때.

코드를 넓게 읽기 전에, 작업 유형에 맞는 시작 위치를 고르기 위한 지도입니다.
레이어 경계나 의존성 규칙이 필요하면 `docs/agent/architecture.md`를 함께 읽습니다.

## 앱 구조

GoldTime은 메인 iOS 앱 1개와 Screen Time 관련 extension 3개로 구성됩니다.

| Target | 역할 | 주요 경로 |
| --- | --- | --- |
| `GoldTime` | 메인 SwiftUI 앱 | `GoldTime/GoldTime/` |
| `DeviceActivityMonitorExtension` | Screen Time interval / threshold 콜백 수신 | `GoldTime/DeviceActivityMonitorExtension/` |
| `ShieldConfigurationExtension` | 시스템 Shield 화면 커스텀 | `GoldTime/ShieldConfigurationExtension/` |
| `ShieldActionExtension` | Shield 버튼 액션과 앱 복귀 알림 처리 | `GoldTime/ShieldActionExtension/` |
| `GoldTimeTests`, `GoldTimeUITests` | 테스트 타겟 | `GoldTime/GoldTimeTests/`, `GoldTime/GoldTimeUITests/` |

## 메인 앱 영역

메인 앱(`GoldTime/GoldTime/`)은 Clean Architecture 5개 레이어로 구성됩니다.

| 영역 | 레이어 | 경로 | 이런 작업에서 먼저 확인 |
| --- | --- | --- | --- |
| 앱 진입점 + DI 조립 | App | `App/GoldTimeApp.swift`, `App/AppDIContainer.swift` | 앱 시작, scene phase, DI 조립, ViewModel 생성 |
| 공유 상태 | Core | `Core/Persistence/SharedStore.swift` | App Group 값, 통계, 카운터, 선택 앱, Shield 상태 |
| Screen Time 조율 | Core | `Core/ScreenTime/ScreenTimeManager.swift` | 모니터링, Shield 적용/해제, 시간 연장, 일일 리셋 |
| 권한 | Core | `Core/Authorization/AuthorizationService.swift` | FamilyControls 권한 상태 |
| 알림 | Core | `Core/Notification/NotificationService.swift` | 로컬 알림 권한과 앱 복귀 알림 |
| 보상형 광고 | Core | `Core/Ads/RewardedAdService.swift` | AdMob 로드, 표시, 보상 콜백 |
| 도메인 모델 | Domain | `Domain/Model/` | ScreenTimeGroup, DailyStats, GroupExtension 타입 |
| Repository 계약 | Domain | `Domain/Repository/` | 데이터 접근 프로토콜 7개 |
| 비즈니스 로직 | Domain | `Domain/UseCase/` | ManageGroups, SyncProtection, LoadDashboard, ExtendGroup, Authorize |
| 그룹 유효성 규칙 | Domain | `Domain/Policy/ScreenTimeGroupPolicy.swift` | 그룹 앱 수 / 한도 / 토큰 타입 판단 |
| Repository 구현체 | Data | `Data/` | Core 서비스 호출, Core ↔ Domain 타입 매핑 |
| 홈 대시보드 | Presentation | `Presentation/Home/HomeView.swift`, `HomeViewModel.swift` | 홈 상태, 그룹 카드, 통계, 보호 상태 |
| 온보딩 | Presentation | `Presentation/Onboarding/OnboardingView.swift` | 권한 요청, 최초 설정 |
| 잠금 선택지 | Presentation | `Presentation/LockOptions/LockOptionsView.swift` | 1분 연장, 광고 해제, 참기 선택지 |
| 광고 화면 | Presentation | `Presentation/RewardedAd/RewardedAdView.swift` | 보상형 광고 표시 래퍼와 fallback UI |
| 공용 UI 컴포넌트 | Presentation | `Presentation/Component/` | 여러 화면에서 반복되는 SwiftUI 컴포넌트와 ButtonStyle |
| 브랜드 스타일 | — | `Extensions/Color+Brand.swift` | Asset Color convenience wrapper |
| 색상 Asset | — | `Assets.xcassets` | `AccentColor`와 `gray100`, `gold100` 같은 Color Set |

## 프로젝트 설정

- Xcode project: `GoldTime/GoldTime.xcodeproj`
- 메인 앱 entitlements: `GoldTime/GoldTime/GoldTime.entitlements`
- Extension entitlements:
  - `GoldTime/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements`
  - `GoldTime/ShieldConfigurationExtension/ShieldConfigurationExtension.entitlements`
  - `GoldTime/ShieldActionExtension/ShieldActionExtension.entitlements`
- 수동 설정 메모: `SETUP.md`

## 작업별 시작점

- UI 문구 또는 레이아웃: 문구/톤은 `docs/agent/product-context.md`, 구현/색상/공용 컴포넌트는 `docs/agent/ui-design-system.md`를 읽고 대상 `Presentation/{화면}/XxxView.swift` 확인.
- 대시보드 통계: `Core/Persistence/SharedStore.swift`, `Presentation/Home/HomeView.swift`, `Domain/UseCase/LoadDashboardUseCase.swift` 확인.
- 1분 연장 동작: `critical-flows.md`, `Core/ScreenTime/ScreenTimeManager.swift`, `Presentation/LockOptions/LockOptionsView.swift`, `Domain/UseCase/ExtendGroupUseCase.swift`, `DeviceActivityMonitorExtension.swift` 확인.
- 광고 해제: `critical-flows.md`, `Core/Ads/RewardedAdService.swift`, `Presentation/RewardedAd/RewardedAdView.swift`, `Domain/UseCase/ExtendGroupUseCase.swift` 확인.
- Shield 화면 또는 버튼: Shield extension 파일들과 `critical-flows.md` 확인.
- 새 기능 레이어 결정: `docs/agent/architecture.md`의 "새 파일을 어느 레이어에 둘지" 표 참고.
- Entitlement 또는 target membership: `SETUP.md`를 읽고 project config 작업으로 취급.
