#!/usr/bin/env bash
# CLAUDE.md(정본)를 같은 폴더의 AGENTS.md로 동기화한다.
# 사용:
#   scripts/sync-agent-docs.sh          # AGENTS.md를 CLAUDE.md 내용으로 갱신
#   scripts/sync-agent-docs.sh --check  # drift가 있으면 비0 종료 (커밋/CI 게이트용)
#
# CLAUDE.md가 있는 모든 폴더가 대상이다(루트 + nested 레이어/타겟). 편집은 항상 CLAUDE.md만,
# AGENTS.md는 생성물로 취급한다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-write}"
status=0

# CLAUDE.md 목록 (build 산출물·.git·DerivedData 제외). 추적/미추적 모두 포함해야 하므로
# git ls-files 대신 find를 쓴다. macOS 기본 bash 3.2 호환을 위해 while-read 사용.
list_claude_files() {
  find . -name CLAUDE.md \
    -not -path '*/build/*' \
    -not -path '*/.git/*' \
    -not -path '*/DerivedData/*'
}

while IFS= read -r claude; do
  [[ -z "$claude" ]] && continue
  agents="$(dirname "$claude")/AGENTS.md"
  if [[ "$MODE" == "--check" ]]; then
    if [[ ! -f "$agents" ]] || ! cmp -s "$claude" "$agents"; then
      echo "drift: $agents 가 $claude 와 다릅니다"
      status=1
    fi
  else
    cp "$claude" "$agents"
    echo "synced: $agents"
  fi
done < <(list_claude_files)

if [[ "$MODE" == "--check" && $status -ne 0 ]]; then
  echo "→ scripts/sync-agent-docs.sh 를 실행해 AGENTS.md를 동기화하세요."
fi
exit $status
