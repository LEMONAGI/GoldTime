# GoldTime TODO — 작업 상태 보드

> 세션 복귀용 단일 출처: "뭐 하던 중이었지 / 다음 뭐 하지 / 실기기로 뭘 확인해야 하지".
> 규칙: 작업 시작 시 "하는 중"에 올리고, 끝나면 **지운다**(완료 기록은 git log가 담당 —
> 여기 쌓지 않는다). 실기기 검증이 남은 채 끝난 작업은 "실기기 검증 대기"에 항목을 남긴다.

## 하는 중

- [ ] 1.2.0 요일별 제한 규칙 (`Feat/WeekdayRules`, 계획: `~/.claude/plans/1-2-0-ancient-swing.md`)
  - [x] 1단계: 모델 + Codable (398e277)
  - [x] 2단계: WeekdayRulePolicy + `resolved(on:)` 투영
  - [x] 3단계: 등록/자정 전환 코어 (리뷰 발견 2건 수정 포함)
  - [x] 4단계: UI (draft 백필 안전장치 포함, 시뮬레이터 육안 확인 권장)
  - [x] 5단계: 알림 요일 트리거 (weekday wrap·64개 제한 dedupe)
  - [x] 6단계: 분석 + 로컬라이징 (로컬라이징은 2·4단계에서 선완료)
  - [ ] 7단계: 실기기 자정 검증 + 문서 + 1.2.0 버전

## 다음 할 일

- [ ] 대시보드(goldtime-dashboard): 1.2.0 신규 분석 값 처리 — rule_kind "weekday",
      weekday_restricted_days(days_N), 코호트 uses_weekday (shield_hit은 집행 규칙 유지라
      rule_kind 조인 시 의미 분화 주의)
- [ ] EU 출시 외부 작업: DSA 거래자 정보, AdMob GDPR 메시지 게시, 처리방침 호스팅
- [ ] Firebase: Run Script 추가·Crashlytics 활성화·AdMob 연동 링크

## 실기기 검증 대기

_(없음 — 앱 진입 시 알림 센터 정리는 2026-07-06 실기기 통과: 쌓인 알림이 앱 진입으로
전부 사라지고 예약 알림은 유지 확인)_

## 아이디어 / 언젠가

- [ ] pre-commit 아키텍처 게이트(역방향 import·`@Published`·hex literal 검사) —
      커밋 리뷰를 skim으로 줄이고 싶어지거나 규칙 위반이 실제로 한 번 새는 날 도입
