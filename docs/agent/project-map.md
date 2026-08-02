# Project Map

Read when: target/경로/entitlement/App Group 같은 프로젝트 설정 위치가 불명확할 때.

Skip when: 작업할 레이어 폴더가 이미 명확할 때(그 폴더의 `CLAUDE.md`가 자동 로드되어 규칙을
가져온다).

레이어별 규칙·함정은 각 폴더의 nested `CLAUDE.md`가 자동으로 알려주므로, 이 문서는 자동
로딩이 못 주는 정보(타겟 목록, 경로, entitlement, App Group, 설정 파일 위치)에 집중합니다.
레이어 경계나 의존성 규칙은 `docs/agent/architecture.md`를 읽습니다.

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
| 앱 진입점 | App | `App/GoldTimeApp.swift` | 앱 시작, scene phase, 루트 ViewModel 소유 (DI는 ViewModel 생성자 기본값 주입 — 컨테이너 없음) |
| 공유 상태 | Core | `Core/Persistence/SharedStore.swift` | App Group 값, 통계, 카운터, 선택 앱, Shield 상태 |
| Screen Time 조율 | Core | `Core/ScreenTime/ScreenTimeManager.swift` | 모니터링, Shield 적용/해제, 시간 연장, 일일 리셋 |
| 권한 | Core | `Core/Authorization/AuthorizationService.swift` | FamilyControls 권한 상태 |
| 알림 | Core | `Core/Notification/NotificationService.swift` | 로컬 알림 권한과 앱 복귀 알림 |
| 보상형 광고 | Core | `Core/Ads/RewardedAdService.swift` | AdMob 로드, 표시, 보상 콜백 |
| 도메인 모델 | Domain | `Domain/Model/` | ScreenTimeGroup, DailyStats, GroupExtension 타입 |
| Repository 계약 | Domain | `Domain/Repository/` | 데이터 접근 프로토콜 |
| 비즈니스 로직 | Domain | `Domain/UseCase/` | 그룹 관리, 보호 동기화, 대시보드, 연장, 권한, 설정 |
| 그룹 유효성 규칙 | Domain | `Domain/Policy/` | 그룹 앱 수 / 한도 / 시간대 / 쿨다운 판단 (extension과 공유) |
| Repository 구현체 | Data | `Data/` | Core 서비스 호출, Core ↔ Domain 타입 매핑 |
| 홈 대시보드 | Presentation | `Presentation/Home/HomeView.swift`, `HomeViewModel.swift` | 홈 상태, 그룹 카드, 통계, 보호 상태 |
| 통계 화면 | Presentation | `Presentation/Stats/StatsView.swift`, `StatsViewModel.swift`, `EmptyChartState.swift` | 스트릭·어제 비교·주간 비교·차트 |
| 잠금 선택지 | Presentation | `Presentation/LockOptions/LockOptionsView.swift` | 1분 연장, 광고 해제, 참기 선택지 |
| 색상 Asset | — | `Assets.xcassets` | `AccentColor`(=`Color.accent`)와 `gray100` Color Set. 색상 규칙은 `docs/agent/ui-design-system.md` |

나머지 화면(Onboarding/RewardedAd/Component 등)은 `Presentation/{화면}/` 규칙이라 폴더를 직접
봅니다 — 이 표는 **이름만으론 위치를 추측하기 어려운 것**만 담습니다.

## 프로젝트 설정

- Xcode project: `GoldTime/GoldTime.xcodeproj`
- 메인 앱 entitlements: `GoldTime/GoldTime/GoldTime.entitlements`
- Extension entitlements:
  - `GoldTime/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements`
  - `GoldTime/ShieldConfigurationExtension/ShieldConfigurationExtension.entitlements`
  - `GoldTime/ShieldActionExtension/ShieldActionExtension.entitlements`
- 수동 설정 메모: `SETUP.md`

## 기능별 핵심 파일

여러 레이어에 걸친 기능의 진입 파일만 모았습니다(같은 폴더의 규칙은 nested `CLAUDE.md` 참고).
런타임 흐름은 `docs/agent/critical-flows.md`를 함께 봅니다.

- 대시보드 통계: `Core/Persistence/SharedStore.swift`, `Presentation/Home/HomeView.swift`, `Domain/UseCase/LoadDashboardUseCase.swift`.
- 통계 화면(이력·추세): `Presentation/Stats/StatsView.swift`·`StatsViewModel.swift`·`EmptyChartState.swift`, `Domain/Repository/StatsRepository.swift`, `Data/StatsRepositoryImpl.swift`. 스트릭 계산은 `LoadDashboardUseCase.calculateAdFreeStreak()`.
- 1분 연장: `Core/ScreenTime/ScreenTimeManager.swift`, `Presentation/LockOptions/LockOptionsView.swift`, `Domain/UseCase/ExtendGroupUseCase.swift`, `DeviceActivityMonitorExtension/`.
- 광고 해제: `Core/Ads/RewardedAdService.swift`, `Presentation/RewardedAd/RewardedAdView.swift`, `Domain/UseCase/ExtendGroupUseCase.swift`.
- Shield 화면/버튼: `ShieldConfigurationExtension/`, `ShieldActionExtension/`.
- 새 기능 레이어 결정: `docs/agent/architecture.md`의 "새 파일을 어느 레이어에 둘지" 표.
- Entitlement / target membership: `SETUP.md`(project config 작업으로 취급).
