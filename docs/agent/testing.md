# Testing Guide

GoldTime의 테스트 원칙은 "구현 전에 기대 동작과 확인 방법을 먼저 고정한다"입니다. 모든 것을 unit test로 만들 수는 없으므로, 테스트 가능한 로직은 TDD로, Apple 시스템 의존 흐름은 검증 시나리오 우선으로 다룹니다.

## 기본 원칙

1. 동작 변경 전 unit test, regression test, 또는 실기기 검증 시나리오 중 하나를 먼저 정합니다.
2. 테스트 가능한 판단 로직은 Apple framework 호출부에서 분리합니다.
3. Apple framework 호출부는 얇게 유지하고, 복잡한 조건 판단을 넣지 않습니다.
4. 실기기에서 발견한 버그는 가능한 부분을 순수 로직으로 환원해 regression test로 남깁니다.
5. 실행하지 못한 검증은 실패처럼 숨기지 말고 이유와 대체 확인을 기록합니다.

## TDD 적용 대상

먼저 실패하는 테스트를 만들거나 기존 테스트를 기대 동작에 맞게 조정합니다.

- `SharedStore` 통계 계산과 기록.
- 1분 연장 카운터와 일일 리셋 판단.
- 날짜 key 생성/조회 로직.
- 광고/1분 연장으로 기록되는 unlock seconds 계산.
- 순수 helper, formatter, mapper, policy 로직.
- 재현 가능한 로직 버그.

현재 테스트는 Swift Testing 기반이며 `GoldTime/GoldTimeTests/` 아래에 둡니다.

```swift
import Testing
@testable import GoldTime

@Test func recordsExpectedBehavior() {
    // arrange
    // act
    // assert with #expect(...)
}
```

## 검증 시나리오 우선 대상

다음 영역은 Apple 시스템 콜백 자체를 unit test로 증명하려 하지 않습니다. 구현 전에 수동 검증 시나리오를 먼저 씁니다.

- FamilyControls 권한 요청과 시스템 다이얼로그.
- DeviceActivity threshold / interval callback.
- ManagedSettings Shield 적용/해제.
- ShieldConfiguration / ShieldAction extension 동작.
- 알림을 통한 앱 복귀.
- entitlement, App Group, target membership.
- AdMob 실제 광고 표시와 reward callback.

## 실기기 검증 시나리오 템플릿

```text
Scenario:
Device / OS:
Preconditions:
Steps:
Expected result:
Observed result:
Follow-up testable logic:
```

예시:

```text
Scenario: 1분 연장 후 자동 재쉴드
Device / OS: 실제 iPhone, iOS 26+
Preconditions: FamilyControls 허용, 앱 1개 선택, 일일 한도 1분, 알림 허용
Steps: 선택 앱을 한도까지 사용 -> Shield 표시 확인 -> GoldTime 가기 -> 1분 연장 선택 -> 60초 후 선택 앱 열기
Expected result: 1분 동안 Shield가 해제되고, 만료 후 다시 Shield가 표시된다.
Observed result: 미실행
Follow-up testable logic: 카운터 증가, override 만료 시 상태 전이, 통계 기록
```

## 테스트 생략 가능 조건

다음 작업은 자동 테스트를 먼저 쓰지 않아도 됩니다.

- 문서만 수정.
- 단순 문구 변경.
- 의미 있는 자동 테스트가 어려운 순수 시각 조정.
- 빌드 설정 안내처럼 코드 동작이 없는 설명 변경.

그래도 acceptance criteria는 먼저 적고, 완료 보고에 검증 생략 이유를 남깁니다.

## 완료 보고 기준

완료 보고에는 최소 하나를 포함합니다.

- 실행한 unit test 또는 추가한 regression test.
- 실행한 build.
- 수행한 실기기 체크.
- 수행하지 못한 검증과 이유.
