# Working Rules

변경을 어느 정도 조심해서 다뤄야 하는지 판단하는 기준입니다.

## 기본 작업 흐름

1. `AGENTS.md`에서 필요한 가이드를 고릅니다.
2. 수정 전에 관련 코드 경로를 읽습니다.
3. 작업 유형과 위험도를 분류합니다.
4. 동작 변경이면 테스트 또는 검증 시나리오를 먼저 정합니다.
5. 목표를 만족하는 가장 작은 변경을 합니다.
6. 먼저 정한 테스트/시나리오로 실행 또는 확인합니다.
7. 변경 파일, 실행한 검증, 남은 실기기 확인 항목을 보고합니다.

## 작업 유형

| 유형 | 예시 | 테스트 우선순위 |
| --- | --- | --- |
| UI-only | SwiftUI 레이아웃, 문구, 색상 | acceptance criteria 먼저, 가능하면 build 또는 preview 성격의 확인 |
| Shared state | `SharedStore`, 카운터, 통계 | unit test 또는 regression test 먼저 |
| Screen Time / Shield | `ScreenTimeManager`, DeviceActivity, Shield extension | 실기기 검증 시나리오 먼저, 가능한 순수 로직은 unit test |
| Ads | `RewardedAdService`, `AdMockView`, 보상 콜백 | reward/fallback 시나리오 먼저, 가능한 wrapper/helper는 unit test |
| Project config | `.xcodeproj`, SPM, entitlements, App Group | 설정 검증 시나리오 먼저, build와 target membership 검토 |
| Docs-only | Markdown guide, setup note | 링크/경로 일치와 중복 확인 |

## 테스트 우선 규칙

- `SharedStore` 통계, 카운터, 날짜 key, 저장/조회 로직은 테스트를 먼저 작성합니다.
- 순수 계산 로직과 helper/service 로직은 가능하면 red test를 먼저 만듭니다.
- 재현 가능한 버그 수정은 실패하는 regression test를 먼저 추가합니다.
- FamilyControls, DeviceActivity, ManagedSettings Shield, Shield extension, 알림 복귀는 Apple 시스템 콜백 자체를 unit test로 검증하려 하지 않습니다.
- 실기기 의존 흐름은 구현 전에 수동 검증 시나리오를 먼저 쓰고, 판단 가능한 로직만 테스트 가능한 형태로 분리합니다.
- 문서, 단순 문구, 의미 있는 자동 테스트가 어려운 순수 시각 조정은 테스트 선행을 생략할 수 있지만 acceptance criteria는 먼저 정합니다.

## 위험도

- Low: 독립적인 문서, 문구, 공유 상태를 건드리지 않는 단일 view.
- Medium: `SharedStore`를 읽는 UI, 광고 표시, 알림 문구, 테스트.
- High: `SharedStore`, `ScreenTimeManager`, extension, entitlements, target membership, `.xcodeproj`, package dependency.

High-risk 작업은 직렬로 처리하고 명시적인 검증 메모를 남깁니다.

## 가볍게 하지 말 것

- migration/reset 결정 없이 App Group key를 바꾸지 않습니다.
- project config 작업이 아닌데 `.xcodeproj`를 기계적으로 수정하지 않습니다.
- 시뮬레이터 런타임으로 Screen Time 동작이 검증됐다고 보지 않습니다.
- 중앙화할 수 있는 상태 로직을 앱과 extension에 중복 구현하지 않습니다.
- build, signing, simulator, sandbox 실패를 숨기지 않습니다.
- 명시 요청 없이 사용자 변경을 되돌리지 않습니다.

## 검증 명령

로컬 Xcode 상태에 따라 가능한 검증을 선택합니다.

- Scheme 확인: `xcodebuild -list -project GoldTime/GoldTime.xcodeproj`
- 앱 build: `xcodebuild -project GoldTime/GoldTime.xcodeproj -scheme GoldTime build`
- 테스트: `xcodebuild test -project GoldTime/GoldTime.xcodeproj -scheme GoldTime`

Xcode가 제한된 cache에 쓰려 하거나 signing/simulator service 문제로 실패하면, 실패 원인을 기록하고 static review 또는 집중 테스트를 대체 확인으로 사용합니다.

## 완료 보고

최종 보고에는 다음을 포함합니다.

- 무엇을 바꿨는지.
- 먼저 정한 테스트 또는 검증 시나리오가 무엇이었는지.
- 어떤 검증을 실행했는지.
- 로컬에서 검증하지 못한 항목.
- 남은 실기기 확인 항목.
