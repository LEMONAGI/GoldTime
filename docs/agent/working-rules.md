# Working Rules

Read when: 작업 위험도, 검증 수준, 완료 보고 기준을 정해야 할 때.

Skip when: 이미 작고 명확한 문서/문구 수정이며 검증 기준이 자명할 때.

변경을 어느 정도 조심해서 다뤄야 하는지 판단하는 기준입니다.

## 기본 작업 흐름

1. `AGENTS.md`에서 작업 유형, 읽을 상세 문서, 검증 방식을 먼저 고정합니다.
2. 수정 전에 관련 코드 경로와 현재 구현 흐름을 읽습니다.
3. 위험도를 분류하고, high-risk 작업은 직렬로 처리합니다.
4. 목표를 만족하는 가장 작은 변경을 합니다.
5. 먼저 정한 테스트/시나리오로 실행 또는 확인합니다.
6. 변경 파일, 실행한 검증, 실행하지 못한 검증을 보고합니다.

## 작업 유형

| 유형 | 예시 | 먼저 정할 검증 |
| --- | --- | --- |
| UI-only | SwiftUI 레이아웃, 문구, 색상 | acceptance criteria 먼저, 가능하면 build 또는 preview 성격의 확인 |
| Shared state | `SharedStore`, 카운터, 통계 | unit test 또는 regression test 먼저 |
| Screen Time / Shield | `ScreenTimeManager`, DeviceActivity, Shield extension | 실기기 검증 시나리오 먼저, 가능한 순수 로직은 unit test |
| Ads | `RewardedAdService`, `AdMockView`, 보상 콜백 | reward/fallback 시나리오 먼저, 가능한 wrapper/helper는 unit test |
| Project config | `.xcodeproj`, SPM, entitlements, App Group | 설정 검증 시나리오 먼저, build와 target membership 검토 |
| Docs-only | Markdown guide, setup note | 링크/경로 일치와 중복 확인 |

## 검증 선택 규칙

- 순수 로직, 저장/조회, 날짜 key, 카운터, formatter/helper는 unit test 또는 regression test로 확인합니다.
- UI-only 변경은 acceptance criteria를 먼저 쓰고, 가능하면 build로 컴파일 회귀를 확인합니다.
- FamilyControls, DeviceActivity, ManagedSettings Shield, Shield extension, 알림 복귀는 수동/실기기 시나리오를 먼저 정합니다.
- 문서, 단순 문구, 순수 시각 조정은 자동 테스트를 생략할 수 있지만 확인 기준은 먼저 정합니다.
- 자세한 TDD 기준과 실기기 시나리오 템플릿은 `testing.md`를 따릅니다.

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
- 먼저 정한 검증 방식.
- 실행한 검증 명령 또는 수동 확인.
- 실행하지 못한 검증과 이유.
- 남은 실기기 확인 항목이 있으면 그 항목.
