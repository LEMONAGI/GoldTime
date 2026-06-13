---
description: 작업 중 발견한 함정·교훈을 가장 가까운 CLAUDE.md "주의사항"에 누적한다
---

방금 작업에서 얻은 교훈/함정을 문서에 누적해줘. 목적은 **문서를 살아있게** 유지하는 것.

기록할 내용: $ARGUMENTS

## 절차

1. **무엇을 배웠는지 한 줄로 정리.** 코드/디렉토리만 봐도 아는 사실은 적지 말 것 —
   "코드만 봐선 모르는 것"(숨은 의존, 함정, 예외, 왜)만.
   - $ARGUMENTS 가 비어 있으면, 직전 작업에서 막혔거나 의외였던 지점을 후보로 제시하고 확인받아라.

2. **어디에 적을지 결정** (가장 좁은 범위 우선):
   - 특정 레이어/타겟 한정 → 그 폴더의 `CLAUDE.md` (예: `GoldTime/GoldTime/Core/CLAUDE.md`,
     `GoldTime/DeviceActivityMonitorExtension/CLAUDE.md`)
   - 교차 관심사 → 해당 공통 문서 (`docs/agent/critical-flows.md`, `architecture.md`,
     `testing.md`, `product-context.md`, `ui-design-system.md` 등)
   - 프로젝트 전역 규칙 → 루트 `CLAUDE.md`

3. **해당 문서의 "주의사항 (작업 중 발견 시 누적)" 절에 한 줄 추가.** 절이 없으면 만든다.
   중복이면 기존 항목을 보강한다.

4. **누적은 정본인 `CLAUDE.md`에만 적는다.** `AGENTS.md`는 `scripts/sync-agent-docs.sh`가
   맞추므로 직접 건드리지 않는다. (루트 변경 시 sync 실행을 잊지 말 것.)

5. 무엇을 어디에 적었는지 한 줄로 보고. (커밋은 사용자가 지시할 때만)

## 원칙

- 간결하게. 한 항목 = 한 교훈.
- 코드가 진실. 문서가 코드와 어긋나 있었다면 그 줄도 함께 고친다.
