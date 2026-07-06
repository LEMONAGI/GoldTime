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

- [ ] 앱 진입 시 알림 센터 정리 (`Feat/ClearDeliveredNotifications`):
      ① extension 발송 알림(한도 임박·"GoldTime 가기")이 쌓인 상태에서 앱 진입 →
      알림 센터의 GoldTime 알림이 전부 사라지는지(extension 발송분 포함)
      ② 다음날 오전 9시 하루 요약·시간대 알림이 예약대로 계속 도착하는지
      (delivered만 지우고 pending 예약은 미영향 확인)

## 아이디어 / 언젠가

- [ ] pre-commit 아키텍처 게이트(역방향 import·`@Published`·hex literal 검사) —
      커밋 리뷰를 skim으로 줄이고 싶어지거나 규칙 위반이 실제로 한 번 새는 날 도입
