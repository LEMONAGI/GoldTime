# ShieldConfigurationExtension — 위험도 High / 직렬

시스템 Shield 화면에 표시할 문구와 버튼 구성만 담당한다.

## 코드만 봐선 모르는 것

- `SharedStore` 상태는 **읽기만**(쓰기는 ShieldAction/메인 앱/DeviceActivity 책임).
- Extension에서는 **앱을 직접 열 수 없다**. "GoldTime 가기"는 ShieldAction이 open request를
  기록하고 알림을 예약하는 경로다.
- App Group key·Codable 하위 호환 유지.

문구 톤은 `docs/agent/product-context.md`, 전체 흐름은 `docs/agent/critical-flows.md`의
"Shield 복귀 흐름". 실기기 검증 필수.

## 주의사항 (작업 중 발견 시 누적)

- Shield 제목 문구는 **모드 중립 단일 풀(`shieldMessages`)**이다(분기 없음). extension은 막힌
  앱의 잠금 모드를 알 수 없어(타겟에 `SharedStore` 없음, 전역 플래그만 raw로 읽힘) 모드별 분기는
  "다른 그룹이 쿨다운이면 한도 앱도 쿨다운 문구" 같은 거짓 문구를 낳는다 → 모드 특정 표현 금지.
  단, `OpenRequestStore.isPending`(알림 안내)은 잠금 모드가 아닌 별개 상태라 유지한다.
