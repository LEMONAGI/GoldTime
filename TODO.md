# GoldTime TODO — 작업 상태 보드

> 세션 복귀용 단일 출처: "뭐 하던 중이었지 / 다음 뭐 하지 / 실기기로 뭘 확인해야 하지".
> 규칙: 작업 시작 시 "하는 중"에 올리고, 끝나면 **지운다**(완료 기록은 git log가 담당 —
> 여기 쌓지 않는다). 실기기 검증이 남은 채 끝난 작업은 "실기기 검증 대기"에 항목을 남긴다.

## 하는 중

_(없음)_

## 다음 할 일

- [ ] 대시보드(goldtime-dashboard): BigQuery export·credential 연결 후 실데이터 검증
- [ ] EU 출시 외부 작업: DSA 거래자 정보, AdMob GDPR 메시지 게시, 처리방침 호스팅
- [ ] Firebase: Run Script 추가·Crashlytics 활성화·AdMob 연동 링크

## 실기기 검증 대기

- [ ] 쿨다운 반복 연장 영구 잠금 수정(2026-07-05) — `/device-verify` 시나리오:
  1. 쿨다운 예산 소진 → 잠금 → 광고 연장 후 **일부만 사용하고 중단** → 휴식 종료 시각 경과
     → 그룹이 정상 해제되는지
  2. 해제 후 해당 앱 재사용 → 이전 연장 소진으로 인한 재잠금(구버그)이 없는지 + 새 사이클
     예산이 0부터 측정되는지 (OSLog에 "재잠금 스킵(휴식 이미 재충전됨)" 또는 stale tick 흡수)
  3. 휴식 중 연장→소진 2~3회 반복 → 휴식 종료 시각에 정상 해제되는지
  - OSLog: `subsystem:com.nagi.GoldTime` Cooldown/Override 카테고리

## 아이디어 / 언젠가

- [ ] pre-commit 아키텍처 게이트(역방향 import·`@Published`·hex literal 검사) —
      커밋 리뷰를 skim으로 줄이고 싶어지거나 규칙 위반이 실제로 한 번 새는 날 도입
