# GoldTime Agent Guide

GoldTime은 스크린타임 한도를 넘기면 Shield 흐름과 보상형 광고 해제를 통해 사용 시간을 의식하게 만드는 iOS 앱입니다.

`AGENTS.md`와 `CLAUDE.md`는 반드시 동일하게 유지합니다. 이 루트 가이드는 짧게 두고, 자세한 규칙은 `docs/agent/` 문서로 분리합니다.

## 시작 순서

1. 먼저 이 루트 가이드만 읽고 작업 유형을 분류합니다.
2. 읽을 상세 문서를 1-2개만 고릅니다.
3. 기획이 모호하면 `docs/agent/competitive-research.md`를 먼저 확인합니다.
4. 수정 전에 관련 코드를 먼저 확인합니다.
5. 동작 변경 전 검증 방식을 먼저 정합니다.
6. 큰 작업은 작은 step으로 나누고 완료 기준을 정합니다.
7. 공유 상태나 고위험 작업은 병렬이 아니라 직렬로 처리합니다.
8. 변경 유형에 맞게 검증한 뒤 완료를 한국어로 보고합니다.

작업 시작 전에 다음 4가지를 말할 수 있어야 합니다.

- 작업 유형: UI-only, shared state, Screen Time / Shield, ads, project config, docs-only.
- 읽을 상세 문서: 아래 문서 지도에서 고른 1-2개.
- 기획 모호성 여부와 참고 기준: 명확하면 생략하고, 모호하면 `competitive-research.md`와 GoldTime다운 판단 기준을 확인합니다.
- 검증 방식: unit test, regression test, build, 수동/실기기 시나리오, 또는 docs-only 확인.

## 문서 선택 규칙

- 처음에는 상세 문서를 1-2개만 읽고, 진행 중 필요할 때 추가로 엽니다.
- 일반적인 기능 변경은 2-3개까지 자연스럽게 허용합니다.
- 4개 이상 필요하면 왜 필요한지 짧게 설명한 뒤 추가로 읽습니다.
- 문서 전체를 습관적으로 읽지 말고 필요한 섹션만 확인합니다.
- 새 파일 위치나 레이어 경계가 불명확할 때는 `architecture.md`를 먼저 읽습니다.
- 코드 위치가 이미 명확하면 `project-map.md`를 생략합니다.
- 레이어가 이미 명확하면 `architecture.md`를 생략합니다.
- 제품 범위 판단이 없으면 `decision-context.md`를 생략합니다.
- 문구/UX 판단이 없으면 `product-context.md`를 생략합니다.
- Screen Time / Shield / 광고 / App Group을 안 건드리면 `critical-flows.md`를 생략합니다.
- 큰 작업 분해가 필요 없으면 `task-harness.md`를 생략합니다.
- 기획이 모호하거나 경쟁/유사 앱 참고가 필요하면 `competitive-research.md`를 먼저 읽습니다.
- 경쟁 앱 판단은 `decision-context.md`보다 `competitive-research.md`를 우선하고, 제품 범위 확정이 필요할 때만 `decision-context.md`를 함께 읽습니다.
- 문구/UX 톤 확정이 필요하면 `product-context.md`를 함께 읽습니다.
- UI 구현, 공용 컴포넌트, 색상/Asset 판단은 `ui-design-system.md`를 우선합니다.
- UI 판단은 특별한 지시가 없으면 기본 iOS 컴포넌트를 기반으로 HIG와 iOS 26.0 UI/UX에 자연스럽게 맞춥니다.
- `competitive-research.md`로 부족해서 최신 경쟁/유사 앱 리서치를 했다면, 재사용 가치가 있는 관찰과 GoldTime 적용점을 해당 문서에 추가합니다.
- 문서/문구 수정은 루트 가이드와 해당 문서만 읽습니다.
- UI 문구, 톤, 화면 감정 판단은 `product-context.md`를 먼저 읽습니다.
- UI 구현, 기본 컴포넌트, 공용 컴포넌트, 색상 작업은 `ui-design-system.md`를 먼저 읽습니다.
- 코드 위치가 불명확할 때만 `project-map.md`를 추가합니다.
- 순수 로직/테스트 변경은 `testing.md`를 우선하고, 위치가 불명확할 때만 `project-map.md`를 추가합니다.
- Screen Time / Shield / 광고 / App Group 변경은 `critical-flows.md`를 우선하고, 검증 설계가 필요할 때만 `testing.md`를 추가합니다.
- 큰 기능 변경은 `decision-context.md`와 `task-harness.md`를 먼저 보고, 이후 step별로 필요한 문서를 근거와 함께 추가합니다.

## 문서 지도

| 트리거 조건 | 읽을 문서 |
| --- | --- |
| 레이어 경계, 의존 방향, 신규 파일 위치, UseCase/Repository 추가 | `docs/agent/architecture.md` |
| 제품 범위, 하지 않을 일, 큰 방향 판단 | `docs/agent/decision-context.md` |
| 프로젝트 구조, 타겟, 시작 위치만 확인 | `docs/agent/project-map.md` |
| Screen Time, Shield, 광고, App Group 런타임 변경 | `docs/agent/critical-flows.md` |
| 작업 절차, 위험도, 검증 기준 확인 | `docs/agent/working-rules.md` |
| TDD, regression test, 수동/실기기 검증 시나리오 | `docs/agent/testing.md` |
| 큰 작업 분해, step 상태, 병렬 판단 | `docs/agent/task-harness.md` |
| 문구, 톤앤매너, UX 판단 | `docs/agent/product-context.md` |
| iOS UI/HIG, 기본 컴포넌트, 공용 컴포넌트, Asset Color | `docs/agent/ui-design-system.md` |
| 기획 모호성, 경쟁 앱 참고, GoldTime다움 판단 | `docs/agent/competitive-research.md` |

## 수정 전 확인

- 작업 유형을 먼저 분류합니다: UI-only, shared state, Screen Time / Shield, ads, project config, docs-only.
- 수정 예상 파일과 건드리는 핵심 흐름을 말할 수 있어야 합니다.
- UI 작업이면 문구/톤 판단인지, SwiftUI 구현/색상/컴포넌트 판단인지 먼저 구분합니다.
- 기획이 모호한 결정은 경쟁 앱을 그대로 따르지 말고 GoldTime의 비용감, 마찰, Shield 선택 경험에 맞게 해석합니다.
- UI는 특별한 지시가 없으면 기본 iOS 컴포넌트를 기반으로 HIG와 iOS 26.0 UI/UX에 자연스럽게 맞춥니다.
- 날짜/시간, 선택, 설정, 확인 흐름은 `DatePicker`, `Picker`, `Form`, `confirmationDialog` 같은 의미에 맞는 시스템 컴포넌트를 먼저 검토합니다.
- 공용으로 반복될 UI는 `GoldTime/GoldTime/Presentation/Component/` 추출을 검토합니다.
- 새 색상은 `AccentColor`를 제외하고 RGB literal 대신 Asset Color로 추가합니다.
- 동작 변경이면 unit test, regression test, build, 수동/실기기 시나리오 중 하나를 먼저 정합니다.
- `.xcodeproj`, entitlements, App Group, `SharedStore`, `ScreenTimeManager`, extension은 가볍게 수정하지 않습니다.
- 워크트리에 이미 있는 사용자 변경은 보존합니다.

## 검증 원칙

- 순수 로직: 테스트를 먼저 추가하거나 기존 테스트를 먼저 조정합니다.
- 일반 앱 변경: 가능하면 Xcode build를 실행합니다.
- FamilyControls, DeviceActivity, Shield, 알림: 구현 전 검증 시나리오를 먼저 쓰고, 시뮬레이터만으로 완료 처리하지 않습니다.
- 테스트 코드로 대체할 수 없는 실기기 확인 항목이 남으면 완료 보고에 사용자 체크리스트로 적습니다.
- 로컬 캐시, signing, simulator, sandbox 문제로 명령이 실패하면 정확한 한계와 대체 확인 방법을 기록합니다.
