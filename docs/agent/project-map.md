# Project Map

Read when: 수정할 코드 위치, target, 시작 파일이 불명확할 때.

Skip when: 수정 대상 파일을 이미 알고 있거나 제품/검증 판단만 필요할 때.

코드를 넓게 읽기 전에, 작업 유형에 맞는 시작 위치를 고르기 위한 지도입니다.

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

| 영역 | 경로 | 이런 작업에서 먼저 확인 |
| --- | --- | --- |
| 공유 상태 | `GoldTime/GoldTime/Models/SharedStore.swift` | App Group 값, 통계, 카운터, 선택 앱, Shield 상태 |
| Screen Time 조율 | `GoldTime/GoldTime/Services/ScreenTimeManager.swift` | 모니터링, Shield 적용/해제, 시간 연장, 일일 리셋 |
| 권한 | `GoldTime/GoldTime/Services/AuthorizationService.swift` | FamilyControls 권한 상태 |
| 알림 | `GoldTime/GoldTime/Services/NotificationService.swift` | 로컬 알림 권한과 앱 복귀 알림 |
| 보상형 광고 | `GoldTime/GoldTime/Services/RewardedAdService.swift` | AdMob 로드, 표시, 보상 콜백 |
| 대시보드 | `GoldTime/GoldTime/Views/HomeView.swift` | 홈 상태, 컨트롤, 통계 카드, 그래프 |
| 온보딩 | `GoldTime/GoldTime/Views/OnboardingView.swift` | 권한 요청, 최초 설정 |
| 잠금 선택지 | `GoldTime/GoldTime/Views/LockOptionsView.swift` | 1분 연장, 광고 해제, 참기 선택지 |
| 광고 화면 | `GoldTime/GoldTime/Views/AdMockView.swift` | 보상형 광고 표시 래퍼와 fallback UI |
| 앱 진입점 | `GoldTime/GoldTime/GoldTimeApp.swift` | 앱 시작, scene phase, lock sheet 표시 |
| 브랜드 스타일 | `GoldTime/GoldTime/Extensions/Color+Brand.swift` | 골드/블랙/화이트 색상 helper |

## 프로젝트 설정

- Xcode project: `GoldTime/GoldTime.xcodeproj`
- 메인 앱 entitlements: `GoldTime/GoldTime/GoldTime.entitlements`
- Extension entitlements:
  - `GoldTime/DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.entitlements`
  - `GoldTime/ShieldConfigurationExtension/ShieldConfigurationExtension.entitlements`
  - `GoldTime/ShieldActionExtension/ShieldActionExtension.entitlements`
- 수동 설정 메모: `SETUP.md`

## 작업별 시작점

- UI 문구 또는 레이아웃: `docs/agent/product-context.md`를 읽고 대상 `Views/*.swift` 확인.
- 대시보드 통계: `SharedStore.swift`, `HomeView.swift`, 기존 테스트 확인.
- 1분 연장 동작: `critical-flows.md`, `ScreenTimeManager.swift`, `LockOptionsView.swift`, `DeviceActivityMonitorExtension.swift` 확인.
- 광고 해제: `critical-flows.md`, `RewardedAdService.swift`, `AdMockView.swift`, `ScreenTimeManager.swift` 확인.
- Shield 화면 또는 버튼: Shield extension 파일들과 `critical-flows.md` 확인.
- Entitlement 또는 target membership: `SETUP.md`를 읽고 project config 작업으로 취급.
