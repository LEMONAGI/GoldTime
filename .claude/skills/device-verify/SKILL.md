---
name: device-verify
description: 실기기 검증 세션 도우미. 변경 diff와 TODO.md에서 필요한 실기기 검증 항목을 도출하고, 시나리오 런북을 만들어 사용자가 폰에서 수행하도록 단계별 안내한 뒤, 기기 OSLog(subsystem com.nagi.GoldTime)를 파싱해 통과 여부를 판정하고 TODO.md를 갱신한다. "실기기 검증하자", "폰으로 확인하자", "/device-verify" 요청 시 사용.
---

실기기 검증을 **"사람은 손만, 판정은 로그로"** 원칙으로 진행한다.
사용자의 시간을 아끼는 것이 목적이다 — 겹치는 시나리오는 묶고, 불필요한 항목은 근거와 함께
과감히 "실기기 불필요"로 판정한다.

## 1. 범위 결정

- 인자가 있으면 그 기능/브랜치를, 없으면 `git diff`(main 대비 또는 working tree) +
  루트 `TODO.md`의 "실기기 검증 대기" 절을 합쳐 후보를 모은다.
- `docs/agent/working-rules.md`의 위험도 기준으로 거른다:
  - Presentation-only·문구·색상·문서 변경 → **실기기 불필요**. 근거와 함께 보고하고 종료.
  - `SharedStore`/`ScreenTimeManager`/extension/스케줄/광고 변경 → 항목화.
- 항목 간 중복을 묶는다. 예: "Shield가 뜨는가"는 여러 기능의 공통 전제이므로 시나리오 1개로
  통합하고, 각 기능은 그 위에 차이점만 얹는다.

## 2. 런북 생성

`docs/agent/testing.md`의 시나리오 템플릿을 따르되 **Expected log trace** 필드를 추가한다:

```text
Scenario:
Device / OS:
Preconditions:
Steps:               ← 폰에서 누르는 동작만. 관찰·판단을 사람에게 시키지 않는다.
Expected result:
Expected log trace:  ← GTLog 카테고리(DailyLimit/Cooldown/TimeWindow/Override/Shield/Activity)
                        기준 기대 로그 시퀀스
Observed result:
```

- 시나리오당 예상 소요 시간을 적고, 총 15분을 넘으면 위험도 순으로 자른다.
- 대기 시간이 필요한 시나리오(연장 만료 등)는 대기 중 다른 시나리오를 끼워 넣도록 배치한다.

## 3. 수행 안내

- 시나리오를 **한 번에 하나씩**: "지금 X 하세요" → 사용자 완료 응답 대기 → 다음 단계.
- 세션 시작 시각을 기록해 둔다(로그 필터링 범위에 사용).
- 시작 전 확인: 기기에 **디버그 빌드**가 설치돼 있는가(GTLog는 디버그 OSLog 기준),
  기기가 Mac에 연결·신뢰돼 있는가.

## 4. 로그 수집·판정

- 수집(사용자가 직접 실행 — sudo는 인터랙티브라 `!` 프리픽스 안내):
  ```
  ! sudo log collect --device --last 30m --output /tmp/goldtime-verify.logarchive
  ```
- 추출·대조:
  ```
  log show /tmp/goldtime-verify.logarchive --info --debug \
    --predicate 'subsystem == "com.nagi.GoldTime"'
  ```
  결과를 각 시나리오의 Expected log trace와 순서대로 대조한다.
- 수집이 안 되면 fallback: Console.app에서 `subsystem:com.nagi.GoldTime` 필터 후
  복사·붙여넣기를 요청한다.
- 판정은 3단계로만: **통과 / 실패**(어느 단계의 기대 로그가 없는지 명시) / **불명**(로그 부족 —
  이유 명시). 애매한 걸 통과로 반올림하지 않는다.

## 5. 기록

- 각 시나리오의 Observed result를 채워 결과를 보고한다.
- 루트 `TODO.md`의 "실기기 검증 대기"에서 통과 항목을 제거하고, 실패 항목은 원인 메모와 함께
  남긴다.
- 새 함정을 발견하면 `/learn`으로 가장 가까운 `CLAUDE.md`에 누적을 제안한다.
