# ShieldActionExtension — 위험도 High / 직렬

Shield 화면 버튼 액션을 처리하고 앱 복귀 요청을 기록한다.

## 코드만 봐선 모르는 것

- Extension에서는 **앱을 직접 열 수 없다**. "GoldTime 가기"는 `SharedStore`에 open request와
  대상 앱/웹사이트 token을 기록하고 **로컬 알림을 예약**하는 방식이다.
- 메인 앱이 열릴 때 open request를 비우고 필요하면 `LockOptionsView`를 띄운다(token이 속한
  잠긴 그룹을 연장 후보로 표시).
- App Group key·Codable 하위 호환 유지.

전체 흐름은 `docs/agent/critical-flows.md`의 "Shield 복귀 흐름". 실기기 검증 필수.

## 주의사항 (작업 중 발견 시 누적)

- (작업 중 발견한 함정을 한 줄씩 누적)
