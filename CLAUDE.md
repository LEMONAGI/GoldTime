# GoldTime Agent Guide

GoldTime은 스크린타임 한도를 넘기면 Shield 흐름과 보상형 광고 해제를 통해 사용 시간을 의식하게 만드는 iOS 앱입니다.

`AGENTS.md`와 `CLAUDE.md`는 반드시 동일하게 유지합니다. 이 루트 가이드는 짧게 두고, 자세한 규칙은 `docs/agent/` 문서로 분리합니다.

## 시작 순서

1. 먼저 이 루트 가이드만 읽고 작업 유형을 분류합니다.
2. 수정 전에 관련 코드를 먼저 확인합니다.
3. 동작 변경 전 테스트 또는 검증 시나리오를 먼저 정합니다.
4. 큰 작업은 작은 step으로 나누고 완료 기준을 정합니다.
5. 공유 상태나 고위험 작업은 병렬이 아니라 직렬로 처리합니다.
6. 변경 유형에 맞게 검증한 뒤 완료를 한국어로 보고합니다.

## 문서 선택 규칙

- 먼저 루트 가이드만 읽고 작업 유형을 분류합니다.
- 상세 문서는 처음에 1-2개만 고릅니다.
- 일반적인 기능 변경은 2-3개까지 자연스럽게 허용합니다.
- 4개 이상 필요하면 왜 필요한지 짧게 설명한 뒤 추가로 읽습니다.
- 모든 문서를 처음부터 다 읽지 말고, 작업이 진행되며 필요한 문서만 추가로 엽니다.
- 문서 전체를 습관적으로 읽지 말고 필요한 섹션만 확인합니다.
- 코드 위치가 이미 명확하면 `project-map.md`를 생략합니다.
- 제품 범위 판단이 없으면 `decision-context.md`를 생략합니다.
- 문구/UX 판단이 없으면 `product-context.md`를 생략합니다.
- Screen Time / Shield / 광고 / App Group을 안 건드리면 `critical-flows.md`를 생략합니다.
- 큰 작업 분해가 필요 없으면 `task-harness.md`를 생략합니다.

## 문서 지도

| 트리거 조건 | 읽을 문서 |
| --- | --- |
| 제품 범위, 하지 않을 일, 큰 방향 판단 | `docs/agent/decision-context.md` |
| 프로젝트 구조, 타겟, 시작 위치만 확인 | `docs/agent/project-map.md` |
| Screen Time, Shield, 광고, App Group 런타임 변경 | `docs/agent/critical-flows.md` |
| 작업 절차, 위험도, 검증 기준 확인 | `docs/agent/working-rules.md` |
| TDD, regression test, 실기기 검증 시나리오 | `docs/agent/testing.md` |
| 큰 작업 분해, step 상태, 병렬 판단 | `docs/agent/task-harness.md` |
| 문구, 톤앤매너, UX 판단 | `docs/agent/product-context.md` |

## 문서 읽기 예산

- 문서/문구 수정: 루트 가이드와 해당 문서만 읽습니다.
- 단일 UI 변경: `product-context.md` 또는 `project-map.md` 중 하나만 먼저 읽습니다.
- 순수 로직/테스트 변경: `testing.md`를 우선하고, 위치가 불명확할 때만 `project-map.md`를 추가합니다.
- Screen Time / Shield / 광고 / App Group 변경: `critical-flows.md`를 우선하고, 검증 설계가 필요할 때만 `testing.md`를 추가합니다.
- 큰 기능 변경: `decision-context.md`와 `task-harness.md`를 먼저 보고, 이후 step별로 필요한 문서를 근거와 함께 추가합니다.

## 수정 전 확인

- 작업 유형을 먼저 분류합니다: UI-only, shared state, Screen Time / Shield, ads, project config.
- 수정 예상 파일과 건드리는 핵심 흐름을 말할 수 있어야 합니다.
- 동작 변경이면 unit test, regression test, 또는 실기기 검증 시나리오 중 하나를 먼저 정합니다.
- `.xcodeproj`, entitlements, App Group, `SharedStore`, `ScreenTimeManager`, extension은 가볍게 수정하지 않습니다.
- 워크트리에 이미 있는 사용자 변경은 보존합니다.

## 검증 원칙

- 순수 로직: 테스트를 먼저 추가하거나 기존 테스트를 먼저 조정합니다.
- 일반 앱 변경: 가능하면 Xcode build를 실행합니다.
- FamilyControls, DeviceActivity, Shield, 알림: 구현 전 검증 시나리오를 먼저 쓰고, 시뮬레이터만으로 완료 처리하지 않습니다.
- 로컬 캐시, signing, simulator, sandbox 문제로 명령이 실패하면 정확한 한계와 대체 확인 방법을 기록합니다.
