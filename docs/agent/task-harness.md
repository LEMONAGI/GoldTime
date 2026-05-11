# Task Harness

외부 자동화 시스템이 아니라, 큰 요청을 내부적으로 작고 안정적인 step으로 나누기 위한 얇은 하네스 규약입니다.

## 언제 쓰나

다음 중 하나에 해당하면 작업을 step으로 나눕니다.

- 두 개 이상의 target 또는 service를 건드립니다.
- 공유 상태나 앱-extension 연동을 바꿉니다.
- UI, 로직, 테스트, 문서가 섞여 있습니다.
- 파일 또는 흐름 충돌 없이 병렬화할 수 있는 부분이 있습니다.
- 완료 기준을 적어두지 않으면 범위가 흐려질 수 있습니다.

아주 작은 문서/문구 수정은 가볍게 처리합니다.

## Step 카드

의미 있는 step은 다음 항목을 가집니다.

```text
Goal:
Flow:
Expected files:
Acceptance criteria:
Test or scenario first:
Verification:
Parallel:
Conflict risk:
Real-device needed:
Status:
Summary:
```

## Step 상태

| 상태 | 의미 |
| --- | --- |
| `pending` | 아직 시작 전 |
| `completed` | 완료했고 요약이 있음 |
| `blocked` | 사용자 입력, 인증, 실기기, signing, 외부 접근이 필요함 |
| `error` | 시도했지만 실패했으며 실패한 검증이나 이유가 있음 |

## 병렬 기준

다음 두 조건을 모두 만족할 때만 병렬 작업이 가능합니다.

- 서로 다른 파일 또는 명확히 분리된 영역을 수정합니다.
- 같은 핵심 흐름이나 공유 상태 계약을 동시에 바꾸지 않습니다.

병렬에 적합한 예:

- 한 step은 문서를 정리하고 다른 step은 테스트를 추가합니다.
- 공유 상태 변경이 없는 독립적인 SwiftUI view 두 개를 수정합니다.
- UI polish와 관계없는 copy edit을 나눕니다.
- 순수 model 테스트와 문서 업데이트를 나눕니다.

직렬 전용 영역:

- `SharedStore`
- `ScreenTimeManager`
- `DeviceActivityMonitorExtension`
- `ShieldConfigurationExtension`
- `ShieldActionExtension`
- `.xcodeproj`
- entitlements와 App Group 설정
- package dependency

## 큰 작업 권장 흐름

1. 관련 파일과 guide를 탐색합니다.
2. 내부 step 카드를 작성합니다.
3. 각 step마다 unit test, regression test, 또는 실기기 검증 시나리오 중 하나를 먼저 정합니다.
4. 직렬 step과 병렬 가능 step을 나눕니다.
5. 직렬 blocker를 먼저 처리합니다.
6. 충돌하지 않는 side work만 병렬로 진행합니다.
7. 결과를 통합하고 먼저 정한 기준으로 검증합니다.
8. 결과와 남은 risk를 요약합니다.

## Step별 테스트 기준

- `Test or scenario first`에는 구현 전에 무엇으로 기대 동작을 고정했는지 적습니다.
- 순수 로직 step은 새 unit test 또는 수정된 기존 테스트를 우선합니다.
- 버그 수정 step은 가능한 경우 실패하는 regression test를 먼저 둡니다.
- 실기기 의존 step은 사용자가 실제 기기에서 확인할 수 있는 시나리오를 먼저 적습니다.
- 테스트를 생략하는 step은 이유와 acceptance criteria를 명시합니다.

## 하네스에서 빌려온 점

이 규약은 phase/step 기반 하네스의 장점인 명확한 step 경계, 상태, acceptance criteria, 테스트/검증 gate만 빌립니다. 실행 스크립트, 자동 commit, 자동 push는 의도적으로 추가하지 않습니다.
