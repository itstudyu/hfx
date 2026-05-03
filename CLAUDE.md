# hfx

> Meta-harness for Claude Code. (이전 명: `harness-factory`. 운영 디렉토리 `.hfx/`에서 이름 유래.)

새 기능을 위한 계획을 세우고 워커들에게 위임하는 메타-하네스. Claude Code 위에서 동작.

## 사용법

```
/hfx <자연어 요구>      새 작업 시작
/hfx --todos            오늘/내일 할 일
/hfx-upgrade            분기별 표준 갱신
```

## 핵심 원칙 (반드시 준수)

@references/principles.md

원칙 요약:
1. **Think Before Coding** — 가정 명시, 헷갈리면 멈춤
2. **Simplicity First** — 50줄로 충분하면 50줄
3. **Surgical Changes** — 변경은 요청에 직접 추적 가능
4. **Goal-Driven Execution** — 모든 plan.md에 dod 필드 필수

## 워크플로

```
유저 요구 → planner (한국어, 100% 합의)
         → commander (지휘만, 코드 X)
         → workers/ (영어, 격리 컨텍스트)
         → 유저 보고
```

## 디렉토리

- `.claude/agents/planner.md`, `commander.md` — 2개 base 에이전트
- `.claude/agents/planner-refs.yaml` — planner 참조 문서 매핑 (default: docs/structure.md)
- `.claude/agents/workers/` — 사용자 정의 워커. default: `example-worker`, `docs-keeper`
- `.hfx/tickets/{active,done,backlog}/` — 티켓 운영 데이터
- `references/knowledge-pack/` — 외부 레퍼런스 (32개 자료, 분기 갱신)

## 참조 문서 (default)

- `docs/structure.md` — 프로젝트 구조 지도 (docs-keeper가 자동 유지)
- 추가 문서는 `/hfx` 첫 호출 시 부트스트랩 인터랙션으로 등록
- 매핑 파일: `.claude/agents/planner-refs.yaml`
