# Testing Guide

Read when: 동작 변경, regression test, 실기기 검증 시나리오를 정해야 할 때.

Skip when: 문서만 수정하거나 테스트/검증 방식이 이미 명확한 작은 변경일 때.

GoldTime의 원칙은 **"구현 전에 기대 동작과 확인 방법을 먼저 고정한다"**입니다. 모든 것을
unit test로 만들 수는 없으므로, 테스트 가능한 로직은 TDD로, **Apple 시스템 의존 흐름은
검증 시나리오 우선**으로 다룹니다. 실행 명령은 `working-rules.md`의 "검증 명령".

## 이 프로젝트의 경계

- unit test는 **앱 내부의 판단과 기록**을 검증합니다. Apple 시스템 콜백의 성공 자체를 대신
  증명하지 않습니다.
- 그래서 테스트 가능한 판단 로직은 Apple framework 호출부에서 분리하고, 호출부는 얇게
  유지합니다(복잡한 조건 판단을 넣지 않습니다).
- 실기기에서 발견한 버그는 **가능한 부분을 순수 로직으로 환원해 regression test로 남깁니다**.
- 실행하지 못한 검증은 실패처럼 숨기지 말고 이유와 대체 확인을 기록합니다.

테스트는 Swift Testing 기반이며 `GoldTime/GoldTimeTests/` 아래에 둡니다.

## 실기기로만 검증되는 영역

다음은 unit test가 아니라 수동/실기기 검증으로 확인합니다. 구현 **전에** 시나리오를 쓰고,
그중 앱 내부 판단만 별도 테스트로 분리합니다.

- FamilyControls 권한 요청과 시스템 다이얼로그.
- DeviceActivity threshold / interval callback.
- ManagedSettings Shield 적용/해제.
- ShieldConfiguration / ShieldAction extension 동작.
- 알림을 통한 앱 복귀.
- entitlement, App Group, target membership.
- AdMob 실제 광고 표시와 reward callback.

실기기 검증 세션은 `/device-verify` 스킬이 이 템플릿과 OSLog 판정을 함께 진행합니다.

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

## 완료 보고의 실기기 체크리스트

Screen Time / Shield / FamilyControls / AdMob 실제 표시는 자동 테스트가 통과했더라도 완료로
뭉뚱그리지 않습니다. 짧아도 **구체적**으로 적습니다.

- 자동 모니터링 시작: 그룹 저장 후 별도 시작 버튼 없이 한도 도달 Shield가 뜨는지.
- Shield 표시/복귀: Shield 버튼, 알림, GoldTime 복귀가 의도대로 이어지는지.
- 1분/광고 연장 후 재잠금: 연장 시간이 끝난 뒤 같은 그룹이 다시 잠기는지.
- 전체 보호 초기화: Shield/override 상태만 정리되고 그룹 설정과 자동 적용은 유지되는지.

권장 형식:

```text
검증:
- 실행: xcodebuild ... test (전체) / -only-testing:'GoldTimeTests/Suite/이름()' (특정)
- 결과: 통과 (특정 테스트면 xcresult totalTestCount 확인)

실기기에서 확인할 것:
- 실제 iPhone / iOS 26+에서 ...
```
