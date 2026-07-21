# GoldTime TODO — 작업 상태 보드

> 세션 복귀용 단일 출처: "뭐 하던 중이었지 / 다음 뭐 하지 / 실기기로 뭘 확인해야 하지".
> 규칙: 작업 시작 시 "하는 중"에 올리고, 끝나면 **지운다**(완료 기록은 git log가 담당 —
> 여기 쌓지 않는다). 실기기 검증이 남은 채 끝난 작업은 "실기기 검증 대기"에 항목을 남긴다.

## 하는 중

- [ ] **1.2.0 App Store 제출** — 코드·검증 완료(2026-07-21). 남은 것: `main` 푸시,
      아카이브·업로드, ASC "이번 버전의 새로운 기능"에
      [docs/release-notes/1.2.0.md](docs/release-notes/1.2.0.md) ko/en/ja 붙여넣기,
      스크린샷 갱신 여부 판단(요일별 규칙·주간 스트립이 이번 버전 핵심)

## 다음 할 일

- [ ] 대시보드(goldtime-dashboard): 1.2.0 신규 분석 값 처리 — rule_kind "weekday",
      weekday_restricted_days(days_N), 코호트 uses_weekday (shield_hit은 집행 규칙 유지라
      rule_kind 조인 시 의미 분화 주의). 광고 placement `group_edit_gate` 노출 의미가
      1.2.0에서 '편집 진입'→'변경 적용(완료 게이트)'으로 변경 — 노출 수 감소는 UX 개선이지
      이탈이 아님(추이 해석 주석 필요)
- [ ] 시간대 차단 규칙 편집 UX: 시간대 작성 편의성 개선(입력 흐름 다듬기 — 범위 미정)
- [ ] Firebase 콘솔: AdMob 연동 링크 (Crashlytics는 코드 완료 — SDK 링크·`FirebaseApp.configure()`
      ·dSYM 업로드 Run Script 모두 붙어 있음, 2026-07-21 빌드 로그로 확인)

## 실기기 검증 대기

_(없음 — 1.2.0 검증 완료 2026-07-21, 판정 기록은
[docs/verify-1.2.0-runbook.md](docs/verify-1.2.0-runbook.md))_

## 아이디어 / 언젠가

- [ ] pre-commit 아키텍처 게이트(역방향 import·`@Published`·hex literal 검사) —
      커밋 리뷰를 skim으로 줄이고 싶어지거나 규칙 위반이 실제로 한 번 새는 날 도입
- [ ] EU 출시 외부 작업: DSA 거래자 정보, AdMob GDPR 메시지 게시, 처리방침 호스팅
      — 코드는 완료(GDPR 동의 철회·PrivacyInfo·처리방침 링크), 콘솔·외부 작업만 남음.
      **2026-07-21 보류 결정** — 착수 시점 미정. 착수 전 주의: DSA 거래자 정보는 EU 배포
      국가가 켜져 있는 동안 미입력이면 EU 스토어 노출이 막히는 항목이다(EU 배포를 끈
      상태라면 무관). 재개할 때 ASC의 현재 EU 배포 설정부터 확인할 것
