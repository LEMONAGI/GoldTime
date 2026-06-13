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

- (작업 중 발견한 함정을 한 줄씩 누적)
