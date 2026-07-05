# Definition of Done — 작업 종료 규칙

Read when: 작업을 완료로 보고하기 직전 자가 점검할 때.

완료 = "동작했다"가 아니라 "규칙을 지켰고, 검증했고, 못 한 검증을 정직하게 남겼다"이다.

## 모든 작업 공통

- [ ] 의존 방향 위반 없음: `App → Presentation → Domain ← Data → Core`.
- [ ] 레이어 상태 규칙 확인: Domain/Data에 `@Observable`·`@Published` 없음, Presentation이
      Core 서비스를 직접 참조하지 않음.
- [ ] **변경에 가장 가까운 `CLAUDE.md`를 갱신**했다(새 함정·예외·규칙 변경이 있으면 그 위치의
      nested `CLAUDE.md` "주의사항"에 누적). 문서와 코드가 다르면 코드에 맞춰 문서를 고쳤다.
- [ ] 루트 `CLAUDE.md`를 고쳤다면 `scripts/sync-agent-docs.sh`로 `AGENTS.md`를 동기화했다
      (또는 pre-commit 훅이 막지 않는지 확인).

## 순수 로직 (UseCase / Policy / Data / SharedStore 계산)

- [ ] 동작 변경 전 unit test 또는 regression test를 먼저 정했고 실행했다.
- [ ] 실기기 버그는 가능한 부분을 순수 로직으로 환원해 regression test로 남겼다.

## Screen Time / Shield / 광고 (위험도 High)

- [ ] 구현 전 실기기 검증 시나리오를 먼저 썼다(`docs/agent/testing.md` 템플릿).
- [ ] **시뮬레이터 build만으로 완료 처리하지 않았다.** 실기기에서만 확인 가능한 항목은 완료
      보고에 "실기기에서 확인할 것" 체크리스트로 남겼다.
- [ ] App Group key·Codable 구조를 바꿨다면 하위 호환/마이그레이션을 검토했다.
- [ ] High-risk 변경을 직렬로 처리하고 검증 메모를 남겼다.

## UI

- [ ] acceptance criteria를 먼저 정했고 HIG/iOS 26.0 적합성을 확인했다.
- [ ] 기본 iOS 컴포넌트 우선(필요 시 커스텀 이유 기록), 새 색상은 Asset Color.
- [ ] 가능하면 build 또는 preview로 컴파일 회귀를 확인했다.

## 마무리

- [ ] 브랜치 `Type/이슈`, 커밋 `[Type] 한글 설명`(광고 변경은 `[Ad]`).
- [ ] 루트 `TODO.md` 갱신: 완료한 항목 제거, 새로 생긴 할 일 추가, 남은 실기기 검증
      항목은 "실기기 검증 대기"에 기록.
- [ ] 한국어로 완료 보고: 무엇을 바꿨는지, 정한 검증, 실행한 검증, 못 한 검증과 이유,
      남은 실기기 체크리스트.

완료 보고 권장 형식과 실기기 체크리스트 예시는 `docs/agent/testing.md`의 "완료 보고 기준".
