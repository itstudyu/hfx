# hfx (v2)

> Meta-harness for Claude Code. (formerly `harness-factory`)

Claude Code 위에 동작하는 메타-하네스. **planner + commander + 사용자 정의 워커** 구조.

## 사용법

```
/hfx <자연어 요구>      새 작업 시작
/hfx --todos            오늘/내일 할 일
/hfx-upgrade            분기별 표준 갱신
```

## 워크플로

```
유저 요구
   ↓
planner (한국어, 100% 유저 합의)
   ↓
commander (지휘만, 코드 작성 X)
   ↓
workers/* (격리된 sub-agent, 영어)
   ↓
유저 보고
```

## Org Chart

[`.hfx/org-chart.md`](.hfx/org-chart.md) — 워커 추가/삭제 시 자동 갱신 (gitignored, 로컬에서만).

## 디렉토리

- `.claude/agents/planner.md`, `commander.md` — 2개 base 에이전트
- `.claude/agents/planner-refs.yaml` — planner 참조 문서 매핑 (`docs/structure.md` default)
- `.claude/agents/workers/` — 사용자 정의 워커 (자동 발견). default: `example-worker`, `docs-keeper`
- `.hfx/tickets/{active,done,backlog}/` — 티켓 운영 데이터
- `references/knowledge-pack/` — 외부 레퍼런스 32개 자료

## 참조 문서

`/hfx` 첫 호출 시 부트스트랩이 실행되어 `docs/structure.md`(default)와 사용자 지정 문서(coding-rule, backend-rule 등)를 [`planner-refs.yaml`](.claude/agents/planner-refs.yaml)에 매핑합니다. planner는 매 작업 시 `auto-load: always` 항목을 자동 로드, 코드 변경이 끝나면 commander가 docs-keeper를 호출해 `docs/structure.md`를 동기화합니다.

## 워커 추가

`.claude/agents/workers/<role>-<expertise>.md` 추가. 자세한 가이드는
[`.claude/agents/workers/README.md`](.claude/agents/workers/README.md).

## 원칙

[`references/principles.md`](references/principles.md) — Karpathy 4원칙 무조건 준수.

## 라이선스

MIT.
